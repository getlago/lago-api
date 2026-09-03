# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription::AppliedInvoiceCustomSection do
  subject(:applied_invoice_custom_section) do
    create(:subscription_applied_invoice_custom_section)
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:customer) { create_default(:customer) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:subscription) }
  it { is_expected.to belong_to(:invoice_custom_section) }
end
