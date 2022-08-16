# frozen_string_literal: true

namespace :charges do
  desc 'Update Properties for Fixed Fee and Free Units'
  task update_properties_for_free_units: :environment do
    # Notes: We consider that we don’t have any clients with a percentage charge
    # created containing a fixed_amount. All existing charges have fixed_amount
    # and fixed_amount_target with a null value.

    Charge.percentage.where("properties -> 'fixed_amount_target' IS NOT NULL").find_each do |charge|
      charge.properties.delete('fixed_amount_target')
      charge.properties['free_units_per_events'] = nil
      charge.properties['free_units_per_total_aggregation'] = nil
      charge.save!
    end
  end
end
