# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectionResolvable do
  let(:organization) { create(:organization) }

  describe "#connection_routing" do
    def connection_routings
      RecurringTransactionRule
        .where(organization:)
        .includes(
          billing_object_connections: %i[payment_provider_customer integration_customer],
          wallet: [
            billing_object_connections: %i[payment_provider_customer integration_customer],
            customer: %i[payment_provider_customers integration_customers]
          ]
        ).map(&:connection_routing)
    end

    def seed_data(count)
      count.times do
        customer = create(:customer, organization:)
        wallet = create(:wallet, customer:, organization:)
        rule = create(:recurring_transaction_rule, wallet:, organization:)

        create(:stripe_customer, customer:, organization:, is_default: true)
        create(:netsuite_customer, customer:, organization:, is_default: true)
        create(:hubspot_customer, customer:, organization:, is_default: true)

        gocardless = create(:gocardless_customer, customer:, organization:)
        xero = create(:xero_customer, customer:, organization:)

        create(:billing_object_connection, owner: wallet, organization:, category: :payment,
          behavior: :specific, payment_provider_customer: gocardless)

        create(:billing_object_connection, owner: rule, organization:, category: :accounting,
          behavior: :specific, integration_customer: xero)

        create(:billing_object_connection, owner: wallet, organization:, category: :tax, behavior: :skip)
      end
    end

    def count_queries
      count = 0
      counter = ->(_name, _start, _finish, _id, payload) {
        count += 1 unless /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)
      }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }

      count
    end

    it "does not trigger N+1 queries" do
      seed_data(1)
      one = count_queries { connection_routings }

      seed_data(3)
      three = count_queries { connection_routings }

      expect(one).to eq(three)
    end
  end
end
