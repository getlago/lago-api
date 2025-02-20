# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipt, type: :model do
  subject(:payment_receipt) { build(:payment_receipt) }

  it { is_expected.to belong_to(:payment) }
end
