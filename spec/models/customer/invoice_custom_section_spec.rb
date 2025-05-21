# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer::InvoiceCustomSection, type: :model do
  subject(:customer_invoice_custom_section) { create(:customer_invoice_custom_section) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:billing_entity) }
  it { is_expected.to belong_to(:customer) }
  it { is_expected.to belong_to(:invoice_custom_section) }
end
