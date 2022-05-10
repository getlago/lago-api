# frozen_string_literal: true

module ChargeModelAttributesHandler
  # NOTE: Map custom arguments of charge models into the properties hash
  #       of each charges.
  #       - Standard model only has one property `amount_cents`
  #       - Graduated model relies on the the list of `GraduatedRange`
  def prepare_arguments(arguments)
    return arguments if arguments[:charges].blank?

    arguments[:charges].map! do |charge|
      output = charge.to_h

      if output.key?(:amount_cents)
        # NOTE: Standard charge model
        output[:properties] = { amount_cents: output[:amount_cents] }
        output.delete(:amount_cents)
      elsif output.key?(:graduated_ranges)
        # NOTE: Graduated charge model
        output[:properties] = output[:graduated_ranges]
        output.delete(:graduated_ranges)
      end

      output
    end

    arguments
  end
end
