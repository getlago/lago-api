# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118185631_backfill_and_constrain_contract_codes")
require Rails.root.join("db/migrate/20261118185633_set_contract_code_not_null")

RSpec.describe SetContractCodeNotNull, transaction: false do
  subject(:migration) { described_class.new }

  let(:backfill) { BackfillAndConstrainContractCodes.new }
  let(:contract) { create(:contract, code: "user-provided") }

  before do
    ActiveRecord::Base.connection.change_column_null(:contracts, :code, true)
    contract
    backfill.up
  end

  after do
    ActiveRecord::Migration.suppress_messages do
      backfill.up
      migration.up
    end
  end

  it "enforces NOT NULL and removes the temporary check constraint" do
    migration.up

    expect(ActiveRecord::Base.connection.check_constraint_exists?(:contracts, name: "contracts_code_not_null")).to be(false)
    expect do
      Contract.transaction(requires_new: true) do
        contract.update_column(:code, nil) # rubocop:disable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "can roll back both migrations without changing existing codes" do
    migration.up
    migration.down
    backfill.down

    expect(contract.reload.code).to eq("user-provided")
    expect do
      contract.update_column(:code, nil) # rubocop:disable Rails/SkipsModelValidations
    end.not_to raise_error
  end
end
