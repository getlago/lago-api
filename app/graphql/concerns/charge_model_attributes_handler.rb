# frozen_string_literal: true

module ChargeModelAttributesHandler
  # NOTE: Map custom arguments of charge models into the properties hash
  #       of each charges.
  #       - Standard model only has one property `amount_cents`
  #       - Graduated model relies on the the list of `GraduatedRange`
  #       - Package model has properties `amount_cents`, `package_size` and `free_units`
  def prepare_arguments(arguments)
    return arguments if arguments[:charges].blank?

    arguments[:charges].map! do |charge|
      output = charge.to_h

      case output[:charge_model].to_sym
      when :standard
        output[:properties] = { amount_cents: output[:amount_cents] }
      when :graduated
        output[:properties] = output[:graduated_ranges]
      when :package
        output[:properties] = {
          amount_cents: output[:amount_cents],
          package_size: output[:package_size],
          free_units: output[:free_units],
        }
      end

      # NOTE: delete fields used to build properties
      output.delete(:graduated_ranges)
      output.delete(:amount_cents)
      output.delete(:free_units)
      output.delete(:package_size)

      output
    end

    arguments
  end
end
