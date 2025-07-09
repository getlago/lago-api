# frozen_string_literal: true

class Refund < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :payment
  belongs_to :credit_note
  belongs_to :payment_provider, optional: true, class_name: "PaymentProviders::BaseProvider"
  belongs_to :payment_provider_customer, class_name: "PaymentProviderCustomers::BaseCustomer"
  belongs_to :organization
end

# == Schema Information
#
# Table name: refunds
#
#  id                           :uuid             not null, primary key
#  amount_cents                 :bigint           default(0), not null
#  amount_currency              :string           not null
#  status                       :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  credit_note_id               :uuid             not null
#  organization_id              :uuid             not null
#  payment_id                   :uuid             not null
#  payment_provider_customer_id :uuid             not null
#  payment_provider_id          :uuid
#  provider_refund_id           :string           not null
#
# Indexes
#
#  index_refunds_on_credit_note_id                (credit_note_id)
#  index_refunds_on_organization_id               (organization_id)
#  index_refunds_on_payment_id                    (payment_id)
#  index_refunds_on_payment_provider_customer_id  (payment_provider_customer_id)
#  index_refunds_on_payment_provider_id           (payment_provider_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_id => payments.id)
#  fk_rails_...  (payment_provider_customer_id => payment_provider_customers.id)
#  fk_rails_...  (payment_provider_id => payment_providers.id)
#
