# frozen_string_literal: true

module ChargeModelAttributesHandler
  # NOTE: Map custom arguments of charge models into the properties hash
  #       of each charges.
  #       - Standard model only has one property `amount_cents`
  #       - Graduated model has property `graduated_ranges` which relies on the the list of `GraduatedRange`
  #       - Package model has properties `amount_cents`, `package_size` and `free_units`
  #       - Percentage model has properties `rate`, `fixed_amount`, `free_units_per_events`, `free_units_per_total_aggregation`
  #       - Volume model has property `volume_ranges` which relies on the list of `VolumeRange``
  def prepare_arguments(arguments)
    return arguments if arguments[:charges].blank?

    arguments[:charges].map! do |charge|
      output = charge.to_h

      case output[:charge_model].to_sym
      when :standard
        output[:properties] = { amount: output[:amount] }
      when :graduated
        output[:properties] = {
          graduated_ranges: output[:graduated_ranges],
        }
      when :package
        output[:properties] = {
          amount: output[:amount],
          package_size: output[:package_size],
          free_units: output[:free_units],
        }
      when :percentage
        output[:properties] = {
          rate: output[:rate],
          fixed_amount: output[:fixed_amount],
          free_units_per_events: output[:free_units_per_events],
          free_units_per_total_aggregation: output[:free_units_per_total_aggregation],
        }
      when :volume
        output[:properties] = {
          volume_ranges: output[:volume_ranges],
        }
      end

      # NOTE: delete fields used to build properties
      output.delete(:graduated_ranges)
      output.delete(:amount)
      output.delete(:free_units)
      output.delete(:package_size)
      output.delete(:rate)
      output.delete(:fixed_amount)
      output.delete(:free_units_per_events)
      output.delete(:free_units_per_total_aggregation)
      output.delete(:volume_ranges)

      output
    end

    arguments
  end
end
