# frozen_string_literal: true

module PaymentMethodable
  extend ActiveSupport::Concern

  included do
    belongs_to :payment_method, optional: true

    validates :payment_method_id, absence: true, if: -> { manual_payment_method? }
  end
end
