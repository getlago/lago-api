# frozen_string_literal: true

namespace :charges do
  desc 'Set graduated properties to hash and rename volume ranges'
  task update_graduated_properties_to_hash: :environment do
    # Rename existing volume ranges from `ranges: []` to `volume_ranges: []`
    Charge.unscoped.volume.find_each do |charge|
      charge.properties['volume_ranges'] = charge.properties.delete('ranges')
      charge.save!
    end

    # Update graduated charges from array `[]` to hash `graduated_ranges: []`
    Charge.unscoped.graduated.find_each do |charge|
      charge.properties = {graduated_ranges: charge.properties}
      charge.save!
    end
  end
end
