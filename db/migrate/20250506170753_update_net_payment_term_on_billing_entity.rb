# frozen_string_literal: true

class UpdateNetPaymentTermOnBillingEntity < ActiveRecord::Migration[8.0]
  def up
    Organization.where.not(net_payment_term: 0).find_each do |organization|
      organization.default_billing_entity.update!(net_payment_term: organization.net_payment_term)
    end
  end
end
