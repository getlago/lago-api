# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118191148_remove_redundant_contract_external_id_index")

RSpec.describe RemoveRedundantContractExternalIdIndex, transaction: false do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before { ActiveRecord::Migration.suppress_messages { migration.down } }
  after { ActiveRecord::Migration.suppress_messages { migration.up } }

  it "removes the old index and keeps the valid unique index covering the same prefix" do
    migration.up

    expect(connection.index_exists?(:contracts, nil, name: :index_contracts_on_organization_id_and_external_id)).to be(false)
    expect(connection.index_exists?(:contracts, [:organization_id, :external_id, :code],
      name: :index_contracts_on_organization_id_external_id_code, unique: true, valid: true)).to be(true)
    expect { migration.up }.not_to raise_error
  end

  it "restores the original index on rollback and allows rollback to run again" do
    migration.up
    migration.down

    expect(connection.index_exists?(:contracts, [:organization_id, :external_id],
      name: :index_contracts_on_organization_id_and_external_id, unique: false, valid: true)).to be(true)
    expect { migration.down }.not_to raise_error
  end
end
