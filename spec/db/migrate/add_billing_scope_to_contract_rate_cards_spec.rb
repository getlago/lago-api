# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261117151151_add_billing_scope_to_contract_rate_cards")

RSpec.describe AddBillingScopeToContractRateCards do
  subject(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) } }

  let(:existing_card) { create(:contract_rate_card) }
  let(:new_card) { create(:contract_rate_card) }

  before do
    existing_card
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:down) }
  end

  it "preserves segment billing for existing cards and defaults new cards to cycle billing" do
    migrate

    expect(existing_card.reload.billing_scope).to eq("segment")
    expect(new_card.reload.billing_scope).to eq("cycle")
  end
end
