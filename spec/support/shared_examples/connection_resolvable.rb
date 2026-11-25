# frozen_string_literal: true

# Shared coverage for ConnectionResolvable. The including spec must define `let(:resolvable)`,
# a billing object whose customer's default connections are inherited.
RSpec.shared_examples "a connection-resolvable billing object" do |fallback: false|
  let(:resolution_customer) { resolvable.customer }
  let(:organization) { resolution_customer.organization }

  describe "#effective_payment_connection" do
    context "when the customer has a default payment connection" do
      let!(:default_connection) do
        create(:stripe_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_payment_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection" do
        let(:override_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_payment_connection).to eq(override_connection)
        end
      end

      context "when the object pins a connection with a deleted payment_provider_customer" do
        let(:override_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: override_connection)

          override_connection.update(deleted_at: Time.zone.now)
        end

        it "falls back to the default connection" do
          expect(resolvable.effective_payment_connection).to eq(default_connection)
        end
      end

      context "when the object skips the category" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_payment_connection).to be_nil
        end
      end

      if fallback
        context "when fallback_connection is defined to pin a specific connection" do
          let(:fallback_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
              behavior: :specific, payment_provider_customer: fallback_connection)
          end

          it "returns the fallback connection" do
            expect(resolvable.effective_payment_connection).to eq(fallback_connection)
          end
        end

        context "when the object pins a connection with a deleted payment_provider_customer" do
          let(:override_connection) { create(:moneyhash_customer, customer: resolution_customer, organization:) }
          let(:fallback_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
              behavior: :specific, payment_provider_customer: override_connection)
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
              behavior: :specific, payment_provider_customer: fallback_connection)

            override_connection.update(deleted_at: Time.zone.now)
          end

          it "falls back to the fallback_record connection" do
            expect(resolvable.effective_payment_connection).to eq(fallback_connection)
          end
        end

        context "when fallback_connection pins a connection with a deleted payment_provider_customer" do
          let(:fallback_connection) { create(:gocardless_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
              behavior: :specific, payment_provider_customer: fallback_connection)

            fallback_connection.update(deleted_at: Time.zone.now)
          end

          it "falls back to the customer default connection" do
            expect(resolvable.effective_payment_connection).to eq(default_connection)
          end
        end

        context "when fallback_connection is defined as skip" do
          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment, behavior: :skip)
          end

          it "returns nil" do
            expect(resolvable.effective_payment_connection).to be_nil
          end
        end
      end
    end

    context "when the customer has no default payment connection" do
      it "returns nil" do
        expect(resolvable.effective_payment_connection).to be_nil
      end
    end
  end

  describe "#effective_accounting_connection" do
    context "when the customer has a default accounting connection" do
      let!(:default_connection) do
        create(:netsuite_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_accounting_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection" do
        let(:override_connection) { create(:xero_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :accounting,
            behavior: :specific, integration_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_accounting_connection).to eq(override_connection)
        end
      end

      context "when the object skips the category" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :accounting, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_accounting_connection).to be_nil
        end
      end

      if fallback
        context "when fallback_connection is redefined and pins a specific connection" do
          let(:fallback_connection) { create(:xero_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :accounting,
              behavior: :specific, integration_customer: fallback_connection)
          end

          it "returns the fallback connection" do
            expect(resolvable.effective_accounting_connection).to eq(fallback_connection)
          end
        end

        context "when fallback_connection is defined as skip" do
          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :accounting, behavior: :skip)
          end

          it "returns nil" do
            expect(resolvable.effective_accounting_connection).to be_nil
          end
        end
      end
    end

    context "when the customer has no default accounting connection" do
      it "returns nil" do
        expect(resolvable.effective_accounting_connection).to be_nil
      end
    end
  end

  describe "#effective_tax_connection" do
    context "when the customer has a default tax connection" do
      let!(:default_connection) do
        create(:anrok_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_tax_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection", skip: "Unskip it when IntegrationCustomer#only_one_tax_integration_per_customer is removed" do
        let(:override_connection) { create(:avalara_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :tax,
            behavior: :specific, integration_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_tax_connection).to eq(override_connection)
        end
      end

      context "when the object skips the category", skip: "Unskip it when IntegrationCustomer#only_one_tax_integration_per_customer is removed" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :tax, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_tax_connection).to be_nil
        end
      end

      if fallback
        context "when fallback_connection is redefined and pins a specific connection", skip: "Unskip it when IntegrationCustomer#only_one_tax_integration_per_customer is removed" do
          let(:fallback_connection) { create(:avalara_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :tax,
              behavior: :specific, integration_customer: fallback_connection)
          end

          it "returns the fallback connection" do
            expect(resolvable.effective_tax_connection).to eq(fallback_connection)
          end
        end

        context "when fallback_connection is defined as skip", skip: "Unskip it when IntegrationCustomer#only_one_tax_integration_per_customer is removed" do
          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :tax, behavior: :skip)
          end

          it "returns nil" do
            expect(resolvable.effective_tax_connection).to be_nil
          end
        end
      end
    end

    context "when the customer has no default tax connection" do
      it "returns nil" do
        expect(resolvable.effective_tax_connection).to be_nil
      end
    end
  end

  describe "#effective_crm_connection" do
    context "when the customer has a default crm connection" do
      let!(:default_connection) do
        create(:hubspot_customer, customer: resolution_customer, organization:, is_default: true)
      end

      it "returns the customer default" do
        expect(resolvable.effective_crm_connection).to eq(default_connection)
      end

      context "when the object pins a specific connection" do
        let(:override_connection) { create(:salesforce_customer, customer: resolution_customer, organization:) }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :crm,
            behavior: :specific, integration_customer: override_connection)
        end

        it "returns the override connection" do
          expect(resolvable.effective_crm_connection).to eq(override_connection)
        end
      end

      context "when the object skips the category" do
        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :crm, behavior: :skip)
        end

        it "returns nil" do
          expect(resolvable.effective_crm_connection).to be_nil
        end
      end

      if fallback
        context "when fallback_connection is redefined and pins a specific connection" do
          let(:fallback_connection) { create(:salesforce_customer, customer: resolution_customer, organization:) }

          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :crm,
              behavior: :specific, integration_customer: fallback_connection)
          end

          it "returns the fallback connection" do
            expect(resolvable.effective_crm_connection).to eq(fallback_connection)
          end
        end

        context "when fallback_connection is defined as skip" do
          before do
            create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :crm, behavior: :skip)
          end

          it "returns nil" do
            expect(resolvable.effective_crm_connection).to be_nil
          end
        end
      end
    end

    context "when the customer has no default crm connection" do
      it "returns nil" do
        expect(resolvable.effective_crm_connection).to be_nil
      end
    end
  end

  describe "#connection_routing" do
    let!(:default_connection) do
      create(:stripe_customer, customer: resolution_customer, organization:, is_default: true, code: "stripe_default")
    end

    let(:routing) { resolvable.connection_routing.index_by(&:category) }

    it "reports every category" do
      expect(routing.keys).to match_array(%w[payment tax accounting crm])
    end

    context "when the category is inherited from the customer" do
      it "reports inherit with the customer default's code" do
        expect(routing["payment"]).to have_attributes(behavior: "inherit", code: default_connection.code)
      end
    end

    context "when the object pins a specific connection" do
      let(:override_connection) do
        create(:gocardless_customer, customer: resolution_customer, organization:, code: "gocardless_eu")
      end

      before do
        create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
          behavior: :specific, payment_provider_customer: override_connection)
      end

      it "reports specific with the pinned code" do
        expect(routing["payment"]).to have_attributes(behavior: "specific", code: "gocardless_eu")
      end
    end

    context "when the object pins a payment connection with a deleted payment_provider_customer" do
      let(:override_connection) { create(:gocardless_customer, customer: resolution_customer, organization:, code: "gocardless_eu") }

      before do
        create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
          behavior: :specific, payment_provider_customer: override_connection)

        override_connection.update(deleted_at: Time.zone.now)
      end

      it "reports inherit with nil code" do
        expect(routing["payment"]).to have_attributes(behavior: "inherit", code: "stripe_default")
      end
    end

    context "when the object skips the category" do
      before do
        create(:billing_object_connection, owner: resolvable, organization:, category: :payment, behavior: :skip)
      end

      it "reports skip with no code" do
        expect(routing["payment"]).to have_attributes(behavior: "skip", code: nil)
      end
    end

    context "when nothing resolves" do
      before { default_connection.delete }

      it "reports inherit with a nil code" do
        expect(routing).to match(
          "payment" => have_attributes(behavior: "inherit", code: nil),
          "tax" => have_attributes(behavior: "inherit", code: nil),
          "accounting" => have_attributes(behavior: "inherit", code: nil),
          "crm" => have_attributes(behavior: "inherit", code: nil)
        )
      end
    end

    if fallback
      context "when fallback_connection is defined to pin a specific connection" do
        let(:fallback_connection) do
          create(:gocardless_customer, customer: resolution_customer, organization:, code: "gocardless_eu")
        end

        before do
          create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: fallback_connection)
        end

        it "reports specific with the pinned code" do
          expect(routing["payment"]).to have_attributes(behavior: "inherit", code: "gocardless_eu")
        end
      end

      context "when the object pins a connection with a deleted payment_provider_customer" do
        let(:override_connection) { create(:moneyhash_customer, customer: resolution_customer, organization:, code: "moneyhash_eu") }
        let(:fallback_connection) { create(:gocardless_customer, customer: resolution_customer, organization:, code: "gocardless_eu") }

        before do
          create(:billing_object_connection, owner: resolvable, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: override_connection)
          create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: fallback_connection)

          override_connection.update(deleted_at: Time.zone.now)
        end

        it "reports specific with the fallback_record connection pinned code" do
          expect(routing["payment"]).to have_attributes(behavior: "inherit", code: "gocardless_eu")
        end
      end

      context "when fallback_connection pins a connection with a deleted payment_provider_customer" do
        let(:fallback_connection) { create(:gocardless_customer, customer: resolution_customer, organization:, code: "gocardless_eu") }

        before do
          create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment,
            behavior: :specific, payment_provider_customer: fallback_connection)

          fallback_connection.update(deleted_at: Time.zone.now)
        end

        it "reports specific with the customer default connection pinned code" do
          expect(routing["payment"]).to have_attributes(behavior: "inherit", code: "stripe_default")
        end
      end

      context "when fallback_connection is defined as skip" do
        before do
          create(:billing_object_connection, owner: resolvable.fallback_record, organization:, category: :payment, behavior: :skip)
        end

        it "reports inherit behavior with nil code" do
          expect(routing["payment"]).to have_attributes(behavior: "inherit", code: nil)
        end
      end
    end
  end

  describe "before the connection backfill" do
    context "when the customer's only connection is not flagged as default" do
      let!(:only_connection) do
        create(:stripe_customer, customer: resolution_customer, organization:, is_default: false)
      end

      it "resolves it as the customer default" do
        expect(resolvable.effective_payment_connection).to eq(only_connection)
      end

      it "reports it on the routing" do
        routing = resolvable.connection_routing.index_by(&:category)

        expect(routing["payment"]).to have_attributes(behavior: "inherit", code: only_connection.code)
      end
    end

    context "when the customer has several connections and none is flagged as default" do
      before do
        create(:stripe_customer, customer: resolution_customer, organization:, is_default: false)
        create(:gocardless_customer, customer: resolution_customer, organization:, is_default: false)
      end

      it "resolves nothing rather than guessing between them" do
        expect(resolvable.effective_payment_connection).to be_nil
      end
    end

    context "when several connections exist and one is flagged as default" do
      let!(:flagged) do
        create(:gocardless_customer, customer: resolution_customer, organization:, is_default: true)
      end

      before { create(:stripe_customer, customer: resolution_customer, organization:, is_default: false) }

      it "prefers the flagged one" do
        expect(resolvable.effective_payment_connection).to eq(flagged)
      end
    end
  end
end
