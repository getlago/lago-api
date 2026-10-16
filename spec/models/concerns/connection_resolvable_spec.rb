# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectionResolvable do
  let(:organization) { create(:organization) }

  describe "#connection_routing query count" do
    def resolve_all
      Wallet
        .where(organization:)
        .includes(:billing_object_connections, customer: %i[payment_provider_customers integration_customers])
        .to_a
        .each(&:connection_routing)
    end

    def count_queries
      count = 0
      counter = ->(_name, _start, _finish, _id, payload) {
        count += 1 unless /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)
      }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }

      count
    end

    def seed_wallets(count)
      Wallet.where(organization:).delete_all

      count.times do
        customer = create(:customer, organization:)
        create(:stripe_customer, customer:, organization:, is_default: true)
        create(:netsuite_customer, customer:, organization:, is_default: true)
        create(:wallet, customer:, organization:)
      end
    end

    it "does not grow with the size of the collection" do
      seed_wallets(1)
      one = count_queries { resolve_all }

      seed_wallets(5)
      five = count_queries { resolve_all }

      expect(five).to eq(one)
    end
  end
end
