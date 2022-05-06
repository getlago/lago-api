# frozen_string_literal: true

module ChargeModelAttributesHandler
  def prepare_arguments(arguments)
    if arguments[:charges].present?
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
    end

    arguments
  end
end
