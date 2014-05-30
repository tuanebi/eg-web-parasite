=head1 LICENSE

Copyright [2009-2014] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EBeyeSearch;

use strict;
use Data::Dumper;
use EBeyeSearch::EBeyeWSWrapper;
use Data::Page;
use DBI;
use URI::Escape;


my $results_cutoff = 10000;
my $default_pagesize = 10; 


my $debug = 0;
sub new {
  my($class, $hub) = @_;
  my $self = bless {
    hub => $hub,
    ws  => EBeyeSearch::EBeyeWSWrapper->new(),
  }, $class;
  return $self;
}

sub hub            { return $_[0]->{hub} };
sub ws             { return $_[0]->{ws} };
sub query_term     { return $_[0]->hub->param('q') };
sub species        { return $_[0]->hub->param('species') || 'all' };
sub filter_species { return $_[0]->hub->param('filter_species') };
sub collection     { return $_[0]->hub->param('collection') || 'all' };
sub site           { return $_[0]->hub->param('site') || 'ensemblthis' };
sub current_page   { return $_[0]->hub->param('page') || 1 };

sub current_index {
  my $self = shift;
  #(my $index = $self->hub->function) =~ s/_[^_]+$//; # strip last part
  #my $hit_counts = $self->get_hit_counts;
  #$index = (sort keys %$hit_counts)[0] unless exists $hit_counts->{$index};
  #return $index || 'gene';
  return 'gene';		# No index used in ParaSite
}


sub current_unit {
  my $self = shift;
#   my $unit = (split /_/, $self->hub->function)[1];
#   my $index = $self->current_index;
#   my $hit_counts = $self->get_hit_counts;
#   $unit = (sort {$self->unit_sort($a, $b)} keys %{$hit_counts->{$index}->{by_unit}})[0] 
#     unless exists $hit_counts->{$index}->{by_unit}->{$unit};
#   return $unit || $SiteDefs::GENOMIC_UNIT;
	return $SiteDefs::GENOMIC_UNIT;
}

sub current_sitename {
  my $self = shift;
  return $SiteDefs::EBEYE_SITE_NAMES->{lc($self->current_unit)} || $self->current_unit;
}

sub ebeye_query {
  my ($self, $no_genomic_unit) = @_;
  my @parts;
  push @parts, $self->query_term;
  push @parts, 'species:' . $self->species if $self->species ne 'all';
  push @parts, 'collection:' . $self->collection if $self->collection ne 'all';
  return join ' AND ', @parts;
}

sub pager {
  my ($self, $page_size) = @_;
  my $pager = Data::Page->new();
  $pager->total_entries($self->hit_count > 10000 ? 10000 : $self->hit_count);
  $pager->entries_per_page($page_size || 10);
  $pager->current_page($self->current_page);
  return $pager; 
}

sub hit_count {
  my $self = shift;
  return $self->{_hit_count} if defined $self->{_hit_count};
  if ($self->filter_species) {
    # get dynamic hit count based on current species filter
    my $query = sprintf("%s AND genomic_unit:%s AND species:%s",
      $self->ebeye_query,
      $self->current_unit,
      $self->filter_species,
    );
    my $index = $self->current_index;
    foreach my $domain ($self->ws->getDetailedNumberOfResults('wormbaseParasite', $query)) {
      next unless $domain->{domainId} =~ /^wormbaseParasite$/i;
      return $self->{_hit_count} = $domain->{numberOfResults} || 0;
    }
  } else {
    # get cached hit count
    my $hit_counts = $self->get_hit_counts;
    return $self->{_hit_count} = $hit_counts->{$self->current_index}->{by_unit}->{$self->current_unit};
  }
}

sub get_hit_counts {
  my ($self) = @_;
  return $self->{_hit_counts} if $self->{_hit_counts};
  return {} unless $self->query_term;
  my $species_defs = $self->hub->species_defs;
  my $query = $self->ebeye_query;
  my $domains_by_unit;
  my $hit_counts;
  # domain hit counts for each ensemblgenomes unit
  my @units = $self->site =~ /^(ensemblthis|ensemblunit)$/ ? ($species_defs->GENOMIC_UNIT) : @{$SiteDefs::EBEYE_SEARCH_UNITS};
  foreach my $unit (@units) {  
    $domains_by_unit->{$unit} = [$self->ws->getDetailedNumberOfResults('wormbaseParasite', "$query AND genomic_unit:$unit")];
  }
  if ($self->site eq 'ensembl_all') {
    # add in domain hit counts for ensembl (we treat ensembl as a unit)
    eval {
      $domains_by_unit->{ensembl} = [$self->ws->getDetailedNumberOfResults('ensembl', $query)]; 
    };
    warn $@ if $@;
  }
  # rearrange hit counts by index/unit
  foreach my $unit (keys %$domains_by_unit) {
    foreach my $domain (@{$domains_by_unit->{$unit}}) {
      (my $index = $domain->{domainId}) =~ s/^.*_([^_]+)$/$1/; # e.g. ensembl_gene > gene       
      my $index = 'gene';	# No index in ParaSite
      my $count = $domain->{numberOfResults};
      $hit_counts->{$index}->{by_unit}->{$unit} = $count if $count > 0;
    }
  }
  if ($self->species eq 'all' and my $counts = $self->get_species_hit_counts) {
    # add in species hit counts
    $hit_counts->{species}->{by_unit} = $counts;
  }
  if (my $counts = $self->get_seq_region_hit_counts) {
    $hit_counts->{'sequence_region'}->{by_unit} = $counts;
  }
  # calculate totals
  my $grand_total = 0;
  foreach my $index (keys %$hit_counts) {
    my $total = 0;
    foreach my $unit (keys %{$hit_counts->{$index}->{by_unit}}) {
      $total += $hit_counts->{$index}->{by_unit}->{$unit};
    }
    $hit_counts->{$index}->{total} = $total;
    $grand_total += $total;
  }
  $self->{_hit_count_total} = $grand_total;
  if ($debug) {
    warn "\n--- EBEYE get_hit_counts ---\n";
    warn "Site type [" . $self->site . "]\n";
    warn "Units to search [" . join(', ', @units) . "]\n";
    warn "Query [$query]\n";
    warn Data::Dumper->Dump([$hit_counts], ['$hit_counts']) . "\n";
  }
  return $self->{_hit_counts} = $hit_counts;
}

sub get_hits {
  my $self = shift;
  if ($self->current_index eq 'species') {
    return $self->get_species_hits;
  } elsif ($self->current_index eq 'sequence_region') {
    return $self->get_seq_region_hits;
  } else { 
    return $self->get_gene_hits;  
  }  
}

sub get_facet_species {
  my $self         = shift;
  my $index        = $self->current_index;
  my $unit         = $self->current_unit;
  my $domain       = $unit eq 'ensembl' ? "ensembl_$index" : "wormbaseParasite";
  my $query        = $unit eq 'ensembl' ? $self->ebeye_query : $self->ebeye_query . " AND genomic_unit:$unit";
  my $facets       = $self->ws->getFacets($domain, $query);
  my $facet_values = $facets->{facetValues}->{FacetValue};
  $facet_values = [$facet_values] unless ref $facet_values eq 'ARRAY';
  my @taxon_ids    = map {$_->{value}} @{ $facet_values };
  my $dbh          = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db; 
  my @species; 
  if (@taxon_ids < 1000 or $unit eq 'ensembl') {
    @species = @{ $dbh->selectcol_arrayref("SELECT name FROM species_search WHERE taxonomy_id IN ('" . join("', '", @taxon_ids) . "') ORDER BY species") };
  } else {
    # we hit the EBEye facet limit - so present all species instead
    @species = @{ $dbh->selectcol_arrayref("SELECT name FROM species_search WHERE genomic_unit = ?", undef, $unit) };
  }
  return \@species;  
}

sub get_gene_hits {
  my ($self) = @_;
  return {} unless $self->query_term;
  my $index = $self->current_index;
  my $unit = $self->current_unit;
  my $filter_species = $self->filter_species;
  my $domain = $unit eq 'ensembl' ? "ensembl_$index" : "wormbaseParasite";
  my $ws = $self->ws; 
  my $pager = $self->pager;
  my $fields = ['id','name','description','species','featuretype','location','gene_synonym','genomic_unit','system_name','transcript','database'];
  my $query = $self->ebeye_query;
  $query .= " AND genomic_unit:$unit" if $unit ne 'ensembl';
  $query .= " AND species:$filter_species" if $filter_species;
  my $hits = $ws->getResultsAsHashArray($domain, $query, $fields, $pager->first - 1, $pager->entries_per_page);
  $_->{url} = $self->feature2url($_) for (@$hits);
  return $hits;
}

# GeneTrees:
sub get_all_hits {
  my ($self) = @_;
  return {} unless $self->query_term;
  return $self->get_species_hits if $self->current_index eq 'species';
  my $index = $self->current_index;
  my $unit = $self->current_unit;
  my $filter_species = $self->filter_species;
  my $domain = $unit eq 'ensembl' ? "ensembl_$index" : "wormbaseParasite";
  my $ws = $self->ws;
  my $pager = $self->pager;
  my $fields = ['id','name','description','species','featuretype','location','gene_synonym','genomic_unit','system_name','transcript'];
  my $query = $self->ebeye_query;
  $query .= " AND genomic_unit:$unit" if $unit ne 'ensembl';
  $query .= " AND species:$filter_species" if $filter_species;
  my $all_hits;
  foreach my $i (1..$pager->last_page) {
    my $first = $i*$pager->entries_per_page - 10;
    my $hits = $ws->getResultsAsHashArray($domain, $query, $fields, $first, $pager->entries_per_page);
    push @$all_hits, @$hits;
  }
  $_->{url} = $self->feature2url($_) for (@$all_hits);
  return $all_hits;
}
# GeneTrees

sub get_seq_region_hit_counts {
  my ($self) = @_;
  return $self->{_seq_region_hit_counts} if $self->{_seq_region_hit_counts};
  return if !$self->query_term;
  my $species_defs = $self->hub->species_defs;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  my $counts_by_unit;
  my @units = $self->site =~ /(ensemblthis|ensemblunit)/i ? ($species_defs->GENOMIC_UNIT) : @{$SiteDefs::EBEYE_SEARCH_UNITS};
  foreach my $unit (@units) {
    my $sql = "SELECT COUNT(*) FROM seq_region_search WHERE seq_region_name = " . $dbh->quote($self->query_term);
    $sql .= " AND species_name = " . $dbh->quote($self->get_production_name($self->species)) if $self->species ne 'all';
    $sql .= " AND genomic_unit = " . $dbh->quote($unit) if $self->species eq 'all';
    my $count = $dbh->selectrow_array($sql);
    $counts_by_unit->{$unit} = $count if $count > 0;
  }
  return $self->{_sequence_region_hit_counts} = $counts_by_unit;
}

sub get_seq_region_hits {
  my ($self) = @_;
  #warn "get_seq_region_hits\n";
  my $species_defs = $self->hub->species_defs;
  my $pager = $self->pager;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  # sql
  my $sql = "SELECT id, seq_region_name, location, coord_system_name, species_name FROM seq_region_search WHERE seq_region_name = " . $dbh->quote($self->query_term);
  $sql .= " AND species_name = " . $dbh->quote($self->get_production_name($self->species)) if $self->species ne 'all';
  $sql .= " AND genomic_unit = " . $dbh->quote($self->current_unit) if $self->species eq 'all';
  $sql .= sprintf(' LIMIT %s, %s', $pager->first - 1, $pager->entries_per_page);
  my $results = $dbh->selectall_hashref($sql, 'id');
  # get hits
  my @hits;
  foreach my $sr (keys %$results) {
    my $name = $results->{$sr}->{seq_region_name};    
    my $species = $results->{$sr}->{species_name};  
    push (@hits, {
      'featuretype' => 'Sequence region',
      'id' => $sr,
      'name' => $name,
      'url' => sprintf ('%s/Location/View?r=%s', $self->species_path( $species, $self->current_unit ), $results->{$sr}->{location}),
      'location' => $results->{$sr}->{location},
      'coord_system' => $results->{$sr}->{coord_system_name},
      'species' => $self->get_display_name($species),
      'species_path' => $self->species_path( $species, $self->current_unit ),
    });
  }
  return \@hits;
}

sub get_species_hit_counts {
  my ($self) = @_;
  return $self->{_species_hit_counts} if $self->{_species_hit_counts};
  return if !$self->query_term;
  my $species_defs = $self->hub->species_defs;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  my $counts_by_unit;
  my @units = $self->site =~ /(ensemblthis|ensemblunit)/i ? ($species_defs->GENOMIC_UNIT) : @{$SiteDefs::EBEYE_SEARCH_UNITS};
  foreach my $unit (@units) {
    my $sql = "SELECT COUNT(*) FROM species_search WHERE keywords LIKE " . $dbh->quote('%' . $self->query_term . '%');
    $sql .= " AND genomic_unit = " . $dbh->quote($unit);
    $sql .= " AND collection = " . $dbh->quote($self->collection) if $self->collection ne 'all';
    my $count = $dbh->selectrow_array($sql);
    $counts_by_unit->{$unit} = $count if $count > 0;
  }
  return $self->{_species_hit_counts} = $counts_by_unit;
}

sub get_species_hits {
  my ($self) = @_;
  my $pager = $self->pager;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  # sql
  my $sql = "SELECT species, name, assembly_name, taxonomy_id FROM species_search WHERE keywords LIKE " . $dbh->quote('%' . $self->query_term . '%');
  $sql .= " AND collection = " . $dbh->quote($self->collection) if $self->collection ne 'all';
  $sql .= " AND genomic_unit = " . $dbh->quote($self->current_unit);
  $sql .= sprintf(' LIMIT %s, %s', $pager->first - 1, $pager->entries_per_page);
  my $results = $dbh->selectall_hashref($sql, 'species');
  # get hits
  my @hits;
  foreach my $sp (keys %$results) {
    push (@hits, {
      'featuretype' => 'Species',
      'id' => $sp,
      'url' => $self->species_path( $sp, $self->current_unit ),
      'name' => $results->{$sp}->{name},
      'assembly_name' => $results->{$sp}->{assembly_name},
      'taxonomy_id' => $results->{$sp}->{taxonomy_id},
    });
  }
  return \@hits;
}

# Hacky method to make a cross-site species path
sub species_path {
  my ($self, $species, $genomic_unit, $want_ensembl) = @_;
  my $species_defs = $self->hub->species_defs;
  my $path         = $species_defs->species_path(ucfirst($species));
  if ($path =~ /^\/$species/i and !$species_defs->valid_species(ucfirst $species) and $genomic_unit) {
    # there was no direct mapping in current unit, use the genomic_unit to add the subdomin
    my $url = ($SiteDefs::ENSEMBL_PROXY_PORT == 80) ? $SiteDefs::ENSEMBL_SERVERNAME : "$SiteDefs::ENSEMBL_SERVERNAME\:$SiteDefs::ENSEMBL_PORT";
    $path = sprintf 'http://$url/%s', $genomic_unit, $species;
  } 
  # If species is in both Ensembl and EG, then $species_defs->species_path will 
  # return EG url by default - sometimes we know we want ensembl
  $path =~ s/http:\/\/[a-z]+\./http:\/\/www\./ if $want_ensembl;
  return $path;
}

sub feature2url {
  my ($self, $hit) =@_;
  (my $species = ucfirst(lc($hit->{species}))) =~ s/ /_/g;
  $species =~ s/[(|)]//g;
  my %lookup = (
    'GENE' => sub { 
      my $hit = shift;
      my $transcript = ref $hit->{transcript} eq 'ARRAY' ? $hit->{transcript}->[0] : (split /\n/, $hit->{transcript})[0];
      my $url = ($SiteDefs::ENSEMBL_PROXY_PORT == 80) ? $SiteDefs::ENSEMBL_SERVERNAME : "$SiteDefs::ENSEMBL_SERVERNAME\:$SiteDefs::ENSEMBL_PORT";
      my $url = "http://$url/$species/Gene/Summary?g=$hit->{id}";
      $url .= ";r=$hit->{location}" if $hit->{location};
      $url .= ";t=$transcript" if $transcript;
      $url .= ";db=$hit->{database}" if $hit->{database}; 
      return $url;
    },
    #...we only have genes for now...
  );
  my $is_ensembl = ($hit->{domain_source} =~ /ensembl_gene/m);
  #print(Dumper($hit));
  #print $hit->{system_name};
  $hit->{species_path} = $self->species_path($species, $hit->{genomic_unit}, $is_ensembl);
  return eval { $lookup{uc $hit->{featuretype}}($hit) } || '';
}

sub unit_sort {
  my ($self, $a, $b) = @_;
  my $species_defs = $self->hub->species_defs;
  # order units with current site first and Ensembl last 
  my $site = $species_defs->GENOMIC_UNIT;
  return -1 if $a =~ /^$site$/i or $b =~ /^ensembl$/i;
  return  1 if $b =~ /^$site$/i or $a =~ /^ensembl$/i;
  return $a cmp $b;
}

sub query_string {
  my ($self, $extra_args) = @_;
  my $core = sprintf("q=%s;species=%s;collection=%s;site=%s", 
    uri_escape($self->query_term), 
    uri_escape($self->species), 
    uri_escape($self->collection),
    uri_escape($self->site),
  );
  my $extra;
  if (ref $extra_args eq 'HASH') {
    while (my ($key, $value) =  each %{$extra_args}) {
      $extra .= ";$key=$value";
    }
  }
  return $core . $extra;
}

sub get_production_name { 
  my $self = shift;
  my $species_name = shift;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  my $sql = "SELECT species FROM species_search WHERE name = ? LIMIT 1";
  return @{ $dbh->selectrow_arrayref($sql, undef, $species_name) || ['unknown'] };
};

sub get_display_name { 
  my $self = shift;
  my $species = shift;
  my $dbh = new EnsEMBL::Web::DBSQL::WebsiteAdaptor($self->hub)->db;
  my $sql = "SELECT name FROM species_search WHERE species = ? LIMIT 1";
  return @{ $dbh->selectrow_arrayref($sql, undef, $species) || ['unknown'] };
};


1;