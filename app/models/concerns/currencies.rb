# frozen_string_literal: true

module Currencies
  extend ActiveSupport::Concern

  ACCEPTED_CURRENCIES = {
    EUR: 'Euro',
    USD: 'American Dollar',
  }.freeze

  included do
    def self.currency_list
      ACCEPTED_CURRENCIES.keys.map(&:to_s).map(&:upcase)
    end
  end
end
