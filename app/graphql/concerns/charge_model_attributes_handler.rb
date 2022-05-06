# frozen_string_literal: true

module ChargeModelAttributesHandler
  def prepare_arguments(arguments)
    if arguments[:charges].present?
      arguments[:charges].map! do |charge|
        output = charge.to_h
        output[:properties] = output[:graduated_ranges]
        output.delete(:graduated_ranges)
        output
      end
    end

    arguments
  end
end
