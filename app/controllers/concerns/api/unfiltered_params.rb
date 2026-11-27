# frozen_string_literal: true

module Api
  module UnfilteredParams
    private

    def unfiltered(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h
      when Array then value.map { unfiltered(it) }
      else value
      end
    end
  end
end
