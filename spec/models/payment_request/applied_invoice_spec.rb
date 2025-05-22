# frozen_string_literal: true

RSpec.describe PaymentRequest::AppliedInvoice, type: :model do
  subject(:applied_invoice) { build(:payment_request_applied_invoice) }

  it { is_expected.to belong_to(:organization) }
end
