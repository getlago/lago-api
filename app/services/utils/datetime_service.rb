# frozen_string_literal: true

module Utils
  class DatetimeService < BaseService
    def self.valid_format?(datetime)
      datetime.respond_to?(:strftime) || datetime.is_a?(String) && DateTime._strptime(datetime).present?
    end
  end
end
