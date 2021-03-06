=head1 LICENSE

Copyright [2014-2017] EMBL-European Bioinformatics Institute

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

package EnsEMBL::Web::IOWrapper;

use strict;

sub nearest_feature {
### Try to find the nearest feature to the browser's current location
  my $self = shift;

  my $location = $self->hub->param('r') || $self->hub->referer->{'params'}->{'r'}[0];

  my ($browser_region, $browser_start, $browser_end) = $location ? split(':|-', $location)
                                                                  : (0,0,0);
  my ($nearest_region, $nearest_start, $nearest_end, $first_region, $first_start, $first_end);
  my $nearest_distance;
  my $first_done = 0;
  my $count = 0;

  while ($self->parser->next) {
    next if $self->parser->is_metadata;
    my ($seqname, $start, $end) = $self->coords;
    next unless $seqname && $start;
    $count++;

    ## Capture the first feature, in case we don't find anything on the current chromosome
    unless ($first_done) {
      ($first_region, $first_start, $first_end) = ($seqname, $start, $end);
      $first_done = 1;
    }

    ## We only measure distance within the current chromosome
    next unless $seqname eq $browser_region;

    my $feature_distance  = $browser_start > $start ? $browser_start - $start : $start - $browser_start;
    $nearest_start      ||= $start;
    $nearest_distance     = $browser_start > $nearest_start ? $browser_start - $nearest_start
                                                           : $nearest_start - $browser_start;

    if ($feature_distance <= $nearest_distance) {
      $nearest_start = $start;
      $nearest_end   = $end;
    }
  }

  if ($nearest_region) {
    ($nearest_start, $nearest_end) = $self->_adjust_coordinates($nearest_start, $nearest_end);
    return ($nearest_region, $nearest_start, $nearest_end, $count, 'nearest');
  }
  else {
    ($first_start, $first_end) = $self->_adjust_coordinates($first_start, $first_end);
    return ($first_region, $first_start, $first_end, $count, 'first');
  }
}

1;
