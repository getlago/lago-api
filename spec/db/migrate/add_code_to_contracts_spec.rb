# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118155957_add_code_to_contracts")

RSpec.describe AddCodeToContracts do
  subject(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) } }

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

  it "backfills contracts of every status and organization using their Lago IDs" do
    migrate

    [*contracts, foreign_contract].each do |contract|
      expect(contract.reload.code).to eq(contract.id)
    end
    expect(named_contract.reload.code).to eq("user-provided")
  end

  it "can run again without changing existing codes" do
    migrate

    expect { ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) } }
      .not_to change { Contract.order(:id).pluck(:id, :code, :updated_at) }
  end
end
