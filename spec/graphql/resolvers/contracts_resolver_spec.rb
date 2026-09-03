# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:variables) { {} }

  let(:query) do
    <<~GQL
      query($status: [ContractStatusEnum!], $externalCustomerId: String) {
        contracts(limit: 5, status: $status, externalCustomerId: $externalCustomerId) {
          collection { id externalId status }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let!(:active_contract) { create(:contract, organization:, customer:) }
  let!(:pending_contract) { create(:contract, :pending, organization:) }

  before { create(:contract) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the contracts of the organization" do
    response = execution["data"]["contracts"]

    expect(response["collection"].map { it["id"] }).to match_array([active_contract.id, pending_contract.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a status filter" do
    let(:variables) { {status: ["pending"]} }

    it "returns only the matching contracts" do
      expect(execution["data"]["contracts"]["collection"].map { it["id"] }).to eq([pending_contract.id])
    end
  end

  context "with a customer filter" do
    let(:variables) { {externalCustomerId: customer.external_id} }

    it "returns only the customer's contracts" do
      expect(execution["data"]["contracts"]["collection"].map { it["id"] }).to eq([active_contract.id])
    end
  end

  context "when the applied rate cards are requested for several contracts" do
    let(:query) do
      <<~GQL
        query {
          contracts(limit: 10) {
            collection { id appliedRateCardsCount appliedRateCards { id rateCard { id } } }
          }
        }
      GQL
    end

    before do
      [active_contract, pending_contract].each do |c|
        create(:contract_rate_card, organization:, contract: c)
      end
    end

    def count_queries(table)
      queries = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] if payload[:sql].include?(%("#{table}"))
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "loads the cards in one query, not one per contract" do
      cards_queries = count_queries("contract_rate_cards") { execution }

      # one batched query for the whole page, not one per contract
      expect(cards_queries.size).to eq(1)
      counts = execution["data"]["contracts"]["collection"].map { it["appliedRateCardsCount"] }
      expect(counts.sum).to eq(2)
    end
  end
end
