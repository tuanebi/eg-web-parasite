=head1 LICENSE

Copyright [2014-2016] EMBL-European Bioinformatics Institute

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

# $Id: HomePage.pm,v 1.69 2014-01-17 16:02:23 jk10 Exp $

package EnsEMBL::Web::Component::Info::HomePage;

use strict;

use EnsEMBL::Web::Document::HTML::HomeSearch;
use EnsEMBL::Web::DBSQL::ProductionAdaptor;
use EnsEMBL::Web::Component::GenomicAlignments;
use EnsEMBL::Web::RegObj;

use LWP::UserAgent;
use JSON;
use List::MoreUtils qw /first_index/;

use base qw(EnsEMBL::Web::Component);

sub _init {
  my $self = shift;
  $self->cacheable(0);
  $self->ajaxable(0);
}

sub get_external_sources {
  my $self = shift;

  my $hub          = $self->hub;
  my $species_defs = $hub->species_defs;

  my $registry = $species_defs->FILE_REGISTRY_URL || return;

  my $species = $hub->species;
  my $taxid   = $species_defs->TAXONOMY_ID;
  return unless $taxid;

  my $url = $registry . '/restapi/resources?taxid=' . $taxid;
  my $ua  = LWP::UserAgent->new;

  my $response = $ua->get($url);
  if ($response->is_success) {
    if (my $sources = decode_json($response->content)) {
      if ($sources->{'total'}) {
        return $sources->{'sources'};
      }
    }
  }
}

sub external_sources {
  my $self = shift;

  my $sources = $self->get_external_sources;
  return unless $sources;
  
  my $hub          = $self->hub;
  my $species_defs = $hub->species_defs;
  my $html;

  my $table = $self->new_table([], [], {
    data_table        => 1,
    sorting           => ['id asc'],
    exportable        => 1,
    data_table_config => {
      iDisplayLength => 10
    },
#    hidden_columns => [1]
  });

  my @columns = (
    {
      key        => 'id',
      title      => 'Title',
      align      => 'left',
      sort       => 'string',
      priority   => 2147483647,    # Give transcriptid the highest priority as we want it to be the 1st colum
      display_id => '',
      link_text  => ''
    },
    {
      key        => 'desc',
      title      => 'Description',
      align      => 'left',
      sort       => 'string',
      priority   => 147483647,
      display_id => '',
      link_text  => ''
    },
    {
      key        => 'link',
      title      => 'Attach',
      display_id => '',
      link_text  => '',
      sort       => 'no'
    },
  );

  my @rows;

  my $sample_data = $species_defs->SAMPLE_DATA;
  my $region_url  = $species_defs->species_path . '/Location/View?r=' . $sample_data->{'LOCATION_PARAM'};

  foreach my $src (@$sources) {
    my $link = sprintf('<a target="extfiles" href="%s;contigviewbottom=url:%s"><img src="/i/96/region.png" style="height:16px" /></a>', $region_url, $src->{'url'});
    my $row = {
      id   => $src->{'title'},
      desc => $src->{'desc'},
      link => $link
    };
    push @rows, $row;
  }

  @columns = sort { $b->{'priority'} <=> $a->{'priority'} || $a->{'title'} cmp $b->{'title'} || $a->{'link_text'} cmp $b->{'link_text'} } @columns;
  $table->add_columns(@columns);
  $table->add_rows(@rows);

  $html .= '<h3>External resources</h3> <p> The following external datasets can be viewed in the browser. Just click on the attach icon to go to the location view.</p>' . $table->render;

  return $html;

}

sub content {
  my $self         = shift;
  my $hub          = $self->hub;
  my $species_defs = $hub->species_defs;
  my $species      = $hub->species;
  my $img_url      = $self->img_url;
  my $common_name  = $species_defs->SPECIES_COMMON_NAME;
  my $display_name = $species_defs->SPECIES_SCIENTIFIC_NAME;
  my $taxid        = $species_defs->TAXONOMY_ID;
  my $provider_link;

  my @species_parts = split('_', $species);
  my $species_short = "$species_parts[0]\_$species_parts[1]";

  if ($species_defs->PROVIDER_NAME && ref $species_defs->PROVIDER_NAME eq 'ARRAY') {
    my @providers;
    push @providers, map { $hub->make_link_tag(text => $species_defs->PROVIDER_NAME->[$_], url => $species_defs->PROVIDER_URL->[$_]) } 0 .. scalar @{$species_defs->PROVIDER_NAME} - 1;

    if (@providers) {
      $provider_link = join ', ', @providers;
    }
  }
  elsif ($species_defs->PROVIDER_NAME) {
    $provider_link = $hub->make_link_tag(text => $species_defs->PROVIDER_NAME, url => $species_defs->PROVIDER_URL);
  }

  my $html = '
    <div class="column-wrapper">  
        <div class="species-badge">';

  if(-e "$SiteDefs::ENSEMBL_SERVERROOT/eg-web-parasite/htdocs/${img_url}species/64/$species_short.png") {  # Check if the image exists
    $html .= qq(<img src="${img_url}species/64/$species_short.png" alt="" title="$common_name" />) unless $self->is_bacteria;
  }

  my $bioproject = $species_defs->SPECIES_BIOPROJECT;
  my $alias_list = $species_defs->SPECIES_ALTERNATIVE_NAME ? sprintf('(<em>%s</em>)', join(', ', @{$species_defs->SPECIES_ALTERNATIVE_NAME})) : undef; # Alternative names will appear in the order they are inserted to the meta table 
  $html .= qq(<h1><em>$display_name</em> $alias_list</h1>);

  $html .= '<p class="taxon-id">';
  $html .= sprintf('BioProject <a href="http://www.ncbi.nlm.nih.gov/bioproject/%s">%s</a> | ', $bioproject, $bioproject) if $bioproject;
  $html .= "Data Source $provider_link | " if $provider_link && $provider_link !~ /^Unknown$/;
  $html .= sprintf q{Taxonomy ID %s}, $hub->get_ExtURL_link("$taxid", 'UNIPROT_TAXONOMY', $taxid) if $taxid;
  $html .= '</p>';
  $html .= '</div>'; #species-badge

  $html .= EnsEMBL::Web::Document::HTML::HomeSearch->new($hub)->render;

  $html .= '<div class="box-right">';
  
  if ($hub->species_defs->multidb->{'DATABASE_PRODUCTION'}{'NAME'}) {
    $html .= '<div class="round-box info-box unbordered">' . $self->_whatsnew_text . '</div>';
  } elsif (my $ack_text = $self->_other_text('acknowledgement', $species)) {
    $html .= '<div class="plain-box round-box unbordered">' . $ack_text . '</div>';
  }

  $html .= '</div>'; # box-right
  $html .= '</div>'; # column-wrapper

  # Check for other genome projects for this species
  my @alt_projects = $self->_get_alt_projects($display_name, $species);
  my $alt_count = scalar(@alt_projects);
  my $alt_string = '<p>There ';
  $alt_string .= $alt_count == 1 ? "is $alt_count alternative genome project" : "are $alt_count alternative genome projects";
  $alt_string .= " for <em>$display_name</em> available in WormBase ParaSite: ";
  foreach my $alt (@alt_projects) {
    my $bioproj = $species_defs->get_config($alt, 'SPECIES_BIOPROJECT');
    my $provider = $species_defs->get_config($alt, 'PROVIDER_NAME');
    my $summary = $provider;
    $alt_string .= qq(<a href="/$alt/Info/Index/" title="$summary">$bioproj</a> );
  }
  $alt_string .= '</p>';

  # Check for other assembies from this project
  my @alt_projects = $self->_get_alt_strains($display_name, $species);
  my $alt_strain_count = scalar(@alt_projects);
  my $alt_strain_string = '<p>There ';
  $alt_strain_string .= $alt_strain_count == 1 ? "is $alt_strain_count alternative strain from this genome project" : "are $alt_strain_count alternative strains from this genome project";
  $alt_strain_string .= " for <em>$display_name</em> available in WormBase ParaSite: ";
  foreach my $alt (@alt_projects) {
    my $strain = $species_defs->get_config($alt, 'SPECIES_STRAIN');
    my $provider = $species_defs->get_config($alt, 'PROVIDER_NAME');
    my $summary = $provider;
    $alt_strain_string .= qq(<a href="/$alt/Info/Index/" title="$summary">$strain</a> );
  }
  $alt_strain_string .= '</p>';
    
  my $about_text = $self->_other_text('about', $species_short);
  $about_text .= $alt_strain_string if $alt_strain_count > 0;
  $about_text .= $alt_string if $alt_count > 0;
  if ($about_text) {
    $html .= '<div class="column-wrapper"><div class="round-box home-box">'; 
    $html .= "<h2>About <em>$display_name</em> $alias_list</h2>";
    $html .= $about_text;
    $html .= '</div></div>';
  }

  ## ParaSite: add a link back to WormBase
  if ($hub->species_defs->ENSEMBL_SPECIES_SITE->{lc($species)} =~ /^wormbase$/i) {
    my $url = $hub->get_ExtURL_link('[View species at WormBase Central]', uc("$species\_URL"));
    $html .= qq(<div class="wormbase_panel">$url</div>);
  }
  ##

  my @left_sections;
  my @right_sections;
  
  push(@left_sections, $self->_assembly_text);
  push(@left_sections, $self->_genebuild_text) if $species_defs->SAMPLE_DATA && $species_defs->SAMPLE_DATA->{GENE_PARAM};

  if ($self->has_compara or $self->has_pan_compara) {
    push(@left_sections, $self->_compara_text);
  }

  push(@right_sections, sprintf('<h2>Statistics</h2>%s', $self->species_stats));

  push(@right_sections, $self->_assembly_stats);

  push(@left_sections, $self->_resources_text) if $self->_other_text('resources', $species);

  push(@left_sections, $self->_downloads_text);

  push(@left_sections, $self->_tools_text);

  my $other_text = $self->_other_text('other', $species);
  push(@left_sections, $other_text) if $other_text =~ /\w/;

  $html .= '<div class="column-wrapper"><div class="column-two"><div class="column-padding">'; 
  for my $section (@left_sections){
    $html .= sprintf(qq{<div class="round-box home-box">%s</div>}, $section);
  }
  $html .= '</div></div><div class="column-two"><div class="column-padding">';
  for my $section (@right_sections) {
    $html .= sprintf(qq{<div class="round-box home-box">%s</div>}, $section);
  }
  $html .= '</div></div></div>';

  my $ext_source_html = $self->external_sources;
  $html .= '<div class="column-wrapper"><div class="round-box home-box unbordered">' . $ext_source_html . '</div></div>' if $ext_source_html;

  return $html;
}

sub _site_release {
  my $self = shift;
  return $self->hub->species_defs->SITE_RELEASE_VERSION;
}

sub _assembly_text {
  my $self             = shift;
  my $hub              = $self->hub;
  my $species_defs     = $hub->species_defs;
  my $species          = $hub->species;
  my $name             = $species_defs->SPECIES_COMMON_NAME;
  my $img_url          = $self->img_url;
  my $sample_data      = $species_defs->SAMPLE_DATA;
  my $ensembl_version  = $self->_site_release;
  my $current_assembly = $species_defs->ASSEMBLY_NAME;
  my $accession        = $species_defs->ASSEMBLY_ACCESSION;
  my $source           = $species_defs->ASSEMBLY_ACCESSION_SOURCE || 'NCBI';
  my $source_type      = $species_defs->ASSEMBLY_ACCESSION_TYPE;
 #my %archive          = %{$species_defs->get_config($species, 'ENSEMBL_ARCHIVES') || {}};
  my %assemblies       = %{$species_defs->get_config($species, 'ASSEMBLIES') || {}};
  my $previous         = $current_assembly;
  my $assembly_description = $self->_other_text('assembly', $species);
  $assembly_description =~ s/<h2>.*<\/h2>//; # Remove the header

  my $html = '<div class="homepage-icon">';

  if (@{$species_defs->ENSEMBL_CHROMOSOMES || []}) {
    $html .= qq(<a class="nodeco _ht" href="/$species/Location/Genome" title="Go to $name karyotype"><img src="${img_url}96/karyotype.png" class="bordered" /><span>View karyotype</span></a>);
  }

  my $region_text = $sample_data->{'LOCATION_TEXT'};
  my $region_url  = $species_defs->species_path . '/Location/View?r=' . $sample_data->{'LOCATION_PARAM'};

  $html .= qq(<a class="nodeco _ht" href="$region_url" title="Go to $region_text"><img src="${img_url}96/region.png" class="bordered" /><span>Example region</span></a>);
  $html .= '</div>'; #homepage-icon

  my $assembly = $current_assembly;
  if ($accession) {
    $assembly = $hub->get_ExtURL_link($current_assembly, 'ENA', $accession);
  }
  $assembly_description = 'Imported from <a href="http://www.wormbase.org">WormBase</a>' if($species_defs->PROVIDER_NAME =~ /^WormBase$/i && !$assembly_description);
  $html .= "<h2>Genome assembly: $assembly</h2>";
  $html .= "<p>$assembly_description</p>";

#  # Link to assembly mapper
#  if ($species_defs->ENSEMBL_AC_ENABLED) {
#    $html .= sprintf('<a href="%s" class="nodeco"><img src="%s24/tool.png" class="homepage-link" />Convert your data to %s coordinates</a></p>', $hub->url({'type' => 'Tools', 'action' => 'AssemblyConverter'}), $img_url, $current_assembly);
#  }
#  elsif (ref($species_defs->ASSEMBLY_MAPPINGS) eq 'ARRAY') {
#    $html .= sprintf('<a href="%s" class="modal_link nodeco" rel="modal_user_data"><img src="%s24/tool.png" class="homepage-link" />Convert your data to %s coordinates</a></p>', $hub->url({'type' => 'UserData', 'action' => 'SelectFeatures', __clear => 1}), $img_url, $current_assembly);
#  }

#EG no old assemblies
 ## PREVIOUS ASSEMBLIES
 #my @old_archives;
 #
 ## Insert dropdown list of old assemblies
 #foreach my $release (reverse sort keys %archive) {
 #  next if $release == $ensembl_version;
 #  next if $assemblies{$release} eq $previous;

 #  push @old_archives, {
 #    url      => sprintf('http://%s.archive.ensembl.org/%s/', lc $archive{$release},           $species),
 #    assembly => "$assemblies{$release}",
 #    release  => (sprintf '(%s release %s)',                  $species_defs->ENSEMBL_SITETYPE, $release),
 #  };

 #  $previous = $assemblies{$release};
 #}

 ## Combine archives and pre
 #my $other_assemblies;
 #if (@old_archives) {
 #  $other_assemblies .= join '', map qq(<li><a href="$_->{'url'}" class="nodeco">$_->{'assembly'}</a> $_->{'release'}</li>), @old_archives;
 #}

 #my $pre_species = $species_defs->get_config('MULTI', 'PRE_SPECIES');
 #if ($pre_species->{$species}) {
 #  $other_assemblies .= sprintf('<li><a href="http://pre.ensembl.org/%s/" class="nodeco">%s</a> (Ensembl pre)</li>', $species, $pre_species->{$species}[1]);
 #}

 #if ($other_assemblies) {
 #  $html .= qq(
 #    <h3 style="color:#808080;padding-top:8px">Other assemblies</h3>
 #    <ul>$other_assemblies</ul>
 #  );
 #}

  return $html;
}

sub _genebuild_text {
  my $self            = shift;
  my $hub             = $self->hub;
  my $species_defs    = $hub->species_defs;
  my $species         = $hub->species;
  my $img_url         = $self->img_url;
  my $sample_data     = $species_defs->SAMPLE_DATA;
  my $ensembl_version = $self->_site_release;
  my $vega            = $species_defs->get_config('MULTI', 'ENSEMBL_VEGA');
  my $has_vega        = $vega->{$species};
  my $annotation_description = $self->_other_text('annotation', $species);
  $annotation_description =~ s/<h2>.*<\/h2>//; # Remove the header

  my $html = '<div class="homepage-icon">';

  my $gene_text = $sample_data->{'GENE_TEXT'};
  my $gene_url  = $species_defs->species_path . '/Gene/Summary?g=' . $sample_data->{'GENE_PARAM'};
  $html .= qq(<a class="nodeco _ht" href="$gene_url" title="Go to gene $gene_text"><img src="${img_url}96/gene.png" class="bordered" /><span>Example gene</span></a>);

#  my $trans_text = $sample_data->{'TRANSCRIPT_TEXT'};
#  my $trans_url  = $species_defs->species_path . '/Transcript/Summary?t=' . $sample_data->{'TRANSCRIPT_PARAM'};
#  $html .= qq(<a class="nodeco _ht" href="$trans_url" title="Go to transcript $trans_text"><img src="${img_url}96/transcript.png" class="bordered" /><span>Example transcript</span></a>);

  $html .= '</div>'; #homepage-icon

  $html .= "<h2>Gene annotation</h2><p>$annotation_description</p><p><strong>What can I find?</strong> Protein-coding and non-coding genes, splice variants, cDNA and protein sequences, non-coding RNAs.</p>";

  return $html;
}

sub _compara_text {
  my $self            = shift;
  my $hub             = $self->hub;
  my $species_defs    = $hub->species_defs;
  my $species         = $hub->species;
  my $img_url         = $self->img_url;
  my $sample_data     = $species_defs->SAMPLE_DATA;
  my $ensembl_version = $species_defs->SITE_RELEASE_VERSION;

  my $html = '<div class="homepage-icon">';
  
  my $tree_text = $sample_data->{'GENE_TEXT'};
  my $tree_url  = $species_defs->species_path . '/Gene/Compara_Tree?g=' . $sample_data->{'GENE_PARAM'};

  # EG genetree
  $html .= qq(
    <a class="nodeco _ht" href="$tree_url" title="Go to gene tree for $tree_text"><img src="${img_url}96/compara.png" class="bordered" /><span>Example gene tree</span></a>
  ) if $self->has_compara('GeneTree');

  # EG family
  if ($self->is_bacteria) {

    $tree_url = $species_defs->species_path . '/Gene/Gene_families?g=' . $sample_data->{'GENE_PARAM'};
    $html .= qq(
      <a class="nodeco _ht" href="$tree_url" title="Go to gene families for $tree_text"><img src="${img_url}96/gene_families.png" class="bordered" /><span>Gene families</span></a>
    ) if $self->has_compara('Family');

  }
  else {

    $tree_url = $species_defs->species_path . '/Gene/Family?g=' . $sample_data->{'GENE_PARAM'};
    $html .= qq(
      <a class="nodeco _ht" href="$tree_url" title="Go to protein families for $tree_text"><span>Protein families</span></a>
    ) if $self->has_compara('Family');

  }

  # EG pan tree
  $tree_url = $species_defs->species_path . '/Gene/Compara_Tree/pan_compara?g=' . $sample_data->{'GENE_PARAM'};
  if ($self->has_pan_compara('GeneTree')) {
    $html .=
      $self->is_bacteria
      ? qq(<a class="nodeco _ht" href="$tree_url" title="Go to pan-taxonomic gene tree for $tree_text"><img src="${img_url}96/compara.png" class="bordered" /><span>Pan-taxonomic tree</span></a>)
      : qq(<a class="nodeco _ht" href="$tree_url" title="Go to pan-taxonomic gene tree for $tree_text"><span>Pan-taxonomic tree</span></a>);
  }

  # EG pan family
  $tree_url = $species_defs->species_path . '/Gene/Family/pan_compara?g=' . $sample_data->{'GENE_PARAM'};
  $html .= qq(
    <a class="nodeco _ht" href="$tree_url" title="Go to pan-taxonomic protein families for $tree_text"><span>Pan-taxonomic protein families</span></a>
  ) if $self->has_pan_compara('Family');

  # /EG
  $html .= '</div>';

  $html .= '<h2>Comparative genomics</h2>';

  $html .= '<p><strong>What can I find?</strong>  Orthologues, paralogues, and gene trees across multiple species.</p>';

  $html .= qq(<p><a href="/info/Browsing/compara/index.html" class="nodeco"><img src="${img_url}24/info.png" alt="" class="homepage-link" />More information and statistics</a></p>);

  my $aligns = EnsEMBL::Web::Component::GenomicAlignments->new($hub)->content;
  if ($aligns) {
    $html .= sprintf(qq{<p><div class="js_panel"><img src="%s24/info.png" alt="" class="homepage-link" />Genomic alignments [%s]</div></p>}, $img_url, $aligns);
  }
  return $html;
}

# ParaSite specific Downloads section
sub _downloads_text {
  my $self         = shift;
  my $hub          = $self->hub;
  my $species_defs = $hub->species_defs;
  my $species      = $hub->species;
  my $rel          = $species_defs->SITE_RELEASE_VERSION;

  (my $sp_name = $species) =~ s/_/ /;
  my $sp_dir =lc($species);
  my $common = $species_defs->get_config($species, 'SPECIES_COMMON_NAME');
  my $scientific = $species_defs->get_config($species, 'SPECIES_SCIENTIFIC_NAME');

  my $ftp_base_path_stub = $species_defs->SITE_FTP . "/releases/WBPS$rel";

  return unless my ($bioproject) = $species =~ /^.*?_.*?_(.*)$/;
  $bioproject = $species_defs->get_config($species, 'SPECIES_FTP_GENOME_ID');
  my $species_lower = lc(join('_',(split('_', $species))[0..1])); 

  my $html = '<h2>Downloads</h2>';
  $html .= '<ul>';
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.genomic.fa.gz\">Genomic Sequence (FASTA)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.genomic_masked.fa.gz\">Hard-masked Genomic Sequence (FASTA)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.genomic_softmasked.fa.gz\">Soft-masked Genomic Sequence (FASTA)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.annotations.gff3.gz\">Annotations (GFF3)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.protein.fa.gz\">Proteins (FASTA)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.mRNA_transcripts.fa.gz\">Full-length transcripts (FASTA)</a></li>";
  $html .= "<li><a href=\"$ftp_base_path_stub/species/$species_lower/$bioproject/$species_lower.$bioproject.WBPS$rel.CDS_transcripts.fa.gz\">CDS transcripts (FASTA)</a></li>";
  $html .= '</ul>';
  
  return $html;
}

# ParaSite specific Tools section
sub _tools_text {
  my $self            = shift;
  my $hub             = $self->hub;
  my $species_defs    = $hub->species_defs;
  my $species         = $hub->species;
  my $img_url         = $self->img_url;
  my $html;

  $html .= '<h2>Tools</h2>';

  $html .= '<ul>';
  my $blast_url = $hub->url({'type' => 'Tools', 'action' => 'Blast', __clear => 1});
  $html .= qq(<li><a href="$blast_url">Search for sequences in the genome and proteome using BLAST</a></li>);
  $html .= qq(<li><a href="/biomart/martview">Work with lists of data using the WormBase ParaSite BioMart data-mining tool</a></li>);
  $html .= qq(<li><a href="/rest">Programatically access WormBase ParaSite data using the REST API</a></li>);
  my $new_vep = $species_defs->ENSEMBL_VEP_ENABLED;
  $html .= sprintf(
    qq(<li><a href="%s">Predict the effects of variants using the Variant Effect Predictor</a></li>),
    $hub->url({'__clear' => 1, $new_vep ? qw(type Tools action VEP) : qw(type UserData action UploadVariations)}),
    $new_vep ? '' : 'modal_link ',
    $self->img_url
  );
  $html .= '</ul>';

}

# ParaSite specific Resources section
sub _resources_text {
  my $self            = shift;
  my $hub             = $self->hub;
  my $species_defs    = $hub->species_defs;
  my $species         = $hub->species;
  my $img_url         = $self->img_url;
  my $sample_data     = $species_defs->SAMPLE_DATA;
  my $ensembl_version = $species_defs->ENSEMBL_VERSION;
  my $site            = $species_defs->ENSEMBL_SITETYPE;
  my $html;
  my $imported_resources = $self->_other_text('resources', $species);
  $imported_resources =~ s/<h2>.*<\/h2>//; # Remove the header

  $html .= '<h2>Resources</h2>';

  $html .= $imported_resources;

  return $html;
  
}

# ParaSite: assembly stats
sub _assembly_stats {
  my $self = shift;
  my $hub = $self->hub;
  my $sp = $hub->species;

  my $html = qq(
    <div class="js_panel">
      <h2>Assembly Statistics</h2>
      <input type="hidden" class="panel_type" value="AssemblyStats" />
      <input type="hidden" id="assembly_file" value="/ssi/species/assembly_$sp.html" />
      <div id="assembly_stats"></div>
      <p style="font-size: 8pt">This widget has been derived from the <a href="https://github.com/rjchallis/assembly-stats">assembly-stats code</a> developed by the Lepbase project at the University of Edinburgh</p>
    </div>
  );

}



# EG

=head2 _other_text

  Arg[1] : tag name to seek
  Arg[2] : species internal name e.g. Caenorhabditis_elegans
  Return : text from htdocs/ssi/species/about_[species].html bounded by the string: <!-- {tag} -->

=cut

sub _other_text {
  my ($self, $tag, $species) = @_;
  my $file = "/ssi/species/about_${species}.html";
  my $content = (-e "$SiteDefs::ENSEMBL_SERVERROOT/eg-web-parasite/htdocs/$file") ? EnsEMBL::Web::Controller::SSI::template_INCLUDE($self, $file) : '';
  my ($other_text) = $content =~ /^.*?<!--\s*\{$tag\}\s*-->(.*)<!--\s*\{$tag\}\s*-->.*$/ms;
  #ENSEMBL-2535 strip subs
  $other_text =~ s/(\{\{sub_[^\}]*\}\})//mg;
  return $other_text;
}

=head2 _has_compara

  Arg[1]     : Database to check, 'compara' or 'compara_pan_ensembl'
  Arg[2]     : Optional - Type of object to check for, e.g. GeneTree, Family
  Description: Check for existence of Compara data for the sample gene
  Returns    : 0, 1, or number of objects

=cut

sub _has_compara {
  my $self           = shift;
  my $db_name        = shift || 'compara';             
  my $object_type    = shift;                           
  my $hub            = $self->hub;
  my $species_defs   = $hub->species_defs;
  my $sample_gene_id = $species_defs->SAMPLE_DATA ? $species_defs->SAMPLE_DATA->{'GENE_PARAM'} : '';
  my $db             = $hub->database($db_name);
  my $has_compara    = 0;
  
  if ($db) {
    if ($object_type) { 
      if ($sample_gene_id) {
        # check existence of a specific data type for the sample gene
        my $member_adaptor = $db->get_GeneMemberAdaptor;
        my $object_adaptor = $db->get_adaptor($object_type);
  
        if (my $member = $member_adaptor->fetch_by_stable_id($sample_gene_id)) {
          if ($object_type eq 'Family' and $self->is_bacteria) {
            $member = $member->get_all_SeqMembers->[0];
          }
          my $objects = $object_type eq 'Family' ? $object_adaptor->fetch_all_by_GeneMember($member) : $object_adaptor->fetch_all_by_Member($member);
          $has_compara = @$objects;
        }
      }
    } else { 
      # no object type specified, simply check if this species is in the db
      my $genome_db_adaptor = $db->get_GenomeDBAdaptor;
      my $genome_db;
      eval{ 
        $genome_db = $genome_db_adaptor->fetch_by_registry_name($hub->species);
      };
      $has_compara = $genome_db ? 1 : 0;
    }
  }

  return $has_compara;  
}

# shortcuts
sub has_compara     { 
  my $self = shift;
  return $self->_has_compara('compara', @_); 
}

# /EG

# ParaSite

sub _get_alt_projects {
  my ($self, $species, $current) = @_;
  my $species_defs = $ENSEMBL_WEB_REGISTRY->species_defs;
  my @species_list = ();
  foreach ($species_defs->valid_species) {
        if ($species_defs->get_config($_, 'SPECIES_SCIENTIFIC_NAME') eq $species && $_ ne $current && $species_defs->get_config($_, 'SPECIES_BIOPROJECT') ne $species_defs->get_config($current, 'SPECIES_BIOPROJECT')) {
          push(@species_list, $_);
        }
  }
  return sort(@species_list);
}

sub _get_alt_strains {
  my ($self, $species, $current) = @_;
  my $species_defs = $ENSEMBL_WEB_REGISTRY->species_defs;
  my @species_list = ();
  foreach ($species_defs->valid_species) {
        if ($species_defs->get_config($_, 'SPECIES_SCIENTIFIC_NAME') eq $species && $species_defs->get_config($_, 'SPECIES_STRAIN') ne $species_defs->get_config($current, 'SPECIES_STRAIN') && $species_defs->get_config($_, 'SPECIES_BIOPROJECT') eq $species_defs->get_config($current, 'SPECIES_BIOPROJECT')) {
          push(@species_list, $_);
        }
  }
  return sort(@species_list);
}

# /ParaSite

sub _add_gene_counts {
  my ($self,$genome_container,$sd,$cols,$options,$tail,$our_type) = @_;

  my @order           = qw(coding_cnt noncoding_cnt noncoding_cnt/s noncoding_cnt/l noncoding_cnt/m pseudogene_cnt transcript);
  my @suffixes        = (['','~'], ['r',' (incl ~ '.$self->glossary_helptip('readthrough', 'Readthrough').')']);
  my $glossary_lookup = {
    'coding_cnt'        => 'Protein coding',
    'noncoding_cnt/s'   => 'Small non coding gene',
    'noncoding_cnt/l'   => 'Long non coding gene',
    'pseudogene_cnt'    => 'Pseudogene',
    'transcript'        => 'Transcript',
  };

  my @data;
  foreach my $statistic (@{$genome_container->fetch_all_statistics()}) {
    my ($name,$inner,$type) = ($statistic->statistic,'','');
    if($name =~ s/^(.*?)_(r?)(a?)cnt(_(.*))?$/$1_cnt/) {
      ($inner,$type) = ($2,$3);
      $name .= "/$5" if $5;
    }
    next unless $type eq $our_type;
    my $i = first_index { $name eq $_ } @order;
    next if $i == -1;
    ($data[$i]||={})->{$inner} = $self->thousandify($statistic->value);
    $data[$i]->{'_key'} = $name;
    $data[$i]->{'_name'} = $statistic->name if $inner eq '';
    $data[$i]->{'_sub'} = ($name =~ m!/!);
  }

  my $counts = $self->new_table($cols, [], $options);
  foreach my $d (@data) {
    my $value = '';
    foreach my $s (@suffixes) {
      next unless $d->{$s->[0]};
      $value .= $s->[1];
      $value =~ s/~/$d->{$s->[0]}/g;
    }
    next unless $value;
    my $class = '';
    $class = 'row-sub' if $d->{'_sub'};
    my $key = $d->{'_name'};
    $key = $self->glossary_helptip("<b>$d->{'_name'}</b>", $glossary_lookup->{$d->{'_key'}});
    $counts->add_row({ name => $key, stat => $value, options => { class => $class }});
  }
  return "<h3>Gene counts$tail</h3>".$counts->render;
}

1;
