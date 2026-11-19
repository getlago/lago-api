# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118185631_backfill_and_constrain_contract_codes")

RSpec.describe BackfillAndConstrainContractCodes do
  subject(:migration) { described_class.new }

  let(:organization) { create(:organization) }
  let(:contracts) do
    Contract::STATUSES.keys.map { |status| create(:contract, organization:, status:) }
  end
  let(:foreign_contract) { create(:contract) }
  let(:named_contract) { create(:contract, organization:, code: "user-provided") }

  before do
    ActiveRecord::Base.connection.change_column_null(:contracts, :code, true)
    Contract.where(id: [*contracts.map(&:id), foreign_contract.id]).update_all(code: nil, updated_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
    named_contract
  end

  it "backfills remaining codes across statuses and organizations without changing existing codes" do
    expect { migration.up }
      .to change { foreign_contract.reload.updated_at }
      .and not_change { named_contract.reload.updated_at }

    [*contracts, foreign_contract].each do |contract|
      expect(contract.reload.code).to eq(contract.id)
    end
    expect(named_contract.reload.code).to eq("user-provided")
  end

  it "can run again without changing codes or timestamps" do
    migration.up

    expect { migration.up }.not_to change { Contract.order(:id).pluck(:id, :code, :updated_at) }
  end

  it "rejects new null codes before backfilling existing rows" do
    allow(ActiveRecord::Base.connection).to receive(:add_check_constraint).and_wrap_original do |original, *args, **options|
      original.call(*args, **options)

      expect(Contract.where(code: nil)).to exist
      expect do
        Contract.transaction(requires_new: true) do
          named_contract.update_column(:code, nil) # rubocop:disable Rails/SkipsModelValidations
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /contracts_code_not_null/)
    end

    migration.up

    expect(ActiveRecord::Base.connection).to have_received(:add_check_constraint)
  end
end
