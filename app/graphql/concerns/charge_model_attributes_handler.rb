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
        output[:properties] = { amount: output[:amount] }
      when :graduated
        output[:properties] = output[:graduated_ranges]
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
        }
      end

      # NOTE: delete fields used to build properties
      output.delete(:graduated_ranges)
      output.delete(:amount)
      output.delete(:free_units)
      output.delete(:package_size)
      output.delete(:rate)
      output.delete(:fixed_amount)

      output
    end

    arguments
  end
end
