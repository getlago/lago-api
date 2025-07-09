# frozen_string_literal: true

RSpec.describe WalletTarget, type: :model do
  subject(:wallet_target) { build(:wallet_billable_metric) }

  it { is_expected.to belong_to(:organization) }
end
