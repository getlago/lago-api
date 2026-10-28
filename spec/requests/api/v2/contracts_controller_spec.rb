# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  # A contract is never deleted, so it renders no deleted_at.
  let(:flat_keys) do
    %i[
      lago_id external_id lago_customer_id external_customer_id name plan_code status billing_time
      consolidate_invoice purchase_order_number billing_anchor_date effective_billing_anchor_date started_at
      ended_at terminated_at canceled_at skip_invoice_custom_sections created_at updated_at
    ]
  end

  describe "POST /api/v2/contracts" do
    subject { post_with_token(organization, "/api/v2/contracts", {contract: create_params}) }

    let(:create_params) do
      {
        external_customer_id: customer.external_id,
        external_id: "contract-1",
        plan_code: catalog_plan.code
      }
    end

    include_examples "requires API permission", "contract", "write"

    context "with a rate card on the plan" do
      let(:rate_card) { create(:rate_card, organization:) }

      before { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2) }

      it "creates the contract with its materialized rate cards, which a show then expands" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(external_id: "contract-1", plan_code: catalog_plan.code, status: "active")
        expect(json[:contract].keys).to eq(flat_keys)

        get_with_token(organization, "/api/v2/contracts/contract-1", {expands: %w[applied_rate_cards]})

        expect(json[:contract][:applied_rate_cards].sole[:rate_card_code]).to eq(rate_card.code)
      end
    end

    context "with expand" do
      subject { post_with_token(organization, "/api/v2/contracts?expands[]=applied_rate_cards", {contract: create_params}) }

      it "creates nothing, as only show expands" do
        expect { subject }.not_to change(Contract, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: %w[applied_rate_cards]})
      end
    end

    context "with invoicing settings" do
      let(:create_params) { super().merge(consolidate_invoice: false, purchase_order_number: "PO-111") }

      it "persists and returns the settings used to group invoices" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-111")
        expect(organization.contracts.find_by!(external_id: "contract-1")).to have_attributes(
          consolidate_invoice: false, purchase_order_number: "PO-111"
        )
      end
    end

    context "with invoice custom sections" do
      let(:section) { create(:invoice_custom_section, organization:) }
      let(:create_params) { super().merge(invoice_custom_section: {invoice_custom_section_codes: [section.code]}) }

      it "attaches the sections, which a show then expands" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:skip_invoice_custom_sections]).to be(false)
        expect(json[:contract].keys).to eq(flat_keys)

        get_with_token(organization, "/api/v2/contracts/contract-1", {expands: %w[invoice_custom_sections]})

        expect(json[:contract][:invoice_custom_sections].pluck(:lago_id)).to eq([section.id])
      end
    end

    context "without a plan" do
      let(:create_params) { {external_customer_id: customer.external_id, external_id: "contract-1"} }

      it "creates a plan-less contract, without rate cards" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(plan_code: nil)
        expect(organization.contracts.find_by!(external_id: "contract-1").applied_rate_cards).to be_empty
      end
    end

    context "when the customer does not exist" do
      let(:create_params) { super().merge(external_customer_id: "unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "when a live contract already uses the external id" do
      before { create(:contract, organization:, customer:, external_id: "contract-1") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :external_id)).to eq(["value_already_exists"])
      end
    end
  end

  describe "GET /api/v2/contracts" do
    subject { get_with_token(organization, "/api/v2/contracts") }

    let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "read"

    it "lists the flat active contracts" do
      subject

      expect(response).to have_http_status(:success)
      result = json[:contracts].sole
      expect(result.keys).to eq(flat_keys)
      expect(result[:lago_id]).to eq(contract.id)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "with expand" do
      subject { get_with_token(organization, "/api/v2/contracts?expands[]=applied_rate_cards") }

      it "returns a not supported error, as lists never expand" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: %w[applied_rate_cards]})
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :contracts, model: Contract do
      let(:paginated_path) { "/api/v2/contracts" }
      let(:create_paginated_record) { ->(created_at) { create(:contract, organization:, customer:, created_at:) } }
    end

    context "with a pending contract" do
      let!(:pending_contract) { create(:contract, :pending, organization:, customer:) }

      it "lists only active contracts by default" do
        subject

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([contract.id])
      end

      it "lists pending contracts when the status filter asks for them" do
        get_with_token(organization, "/api/v2/contracts?status[]=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end

      it "accepts the scalar status form" do
        get_with_token(organization, "/api/v2/contracts?status=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end
    end

    context "with a billing entity filter" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let!(:matching) { create(:contract, organization:, billing_entity:) }

      it "returns only contracts on that billing entity" do
        get_with_token(organization, "/api/v2/contracts?billing_entity_ids[]=#{billing_entity.id}")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([matching.id])
      end
    end

    context "with a has_rate_overrides filter" do
      it "returns only contracts carrying a rate override" do
        card = create(:contract_rate_card, organization:, contract:)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card, rate_override: create(:rate_override, organization:))

        get_with_token(organization, "/api/v2/contracts?has_rate_overrides=true")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([contract.id])
      end
    end

    context "with a search term" do
      let!(:matching) { create(:contract, organization:, external_id: "needle-1") }

      it "returns only the matching contracts" do
        get_with_token(organization, "/api/v2/contracts?search_term=needle")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([matching.id])
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", params) }

    let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:params) { {} }

    include_examples "requires API permission", "contract", "read"

    context "with an applied rate card and a section" do
      before do
        create(:contract_rate_card, organization:, contract:)
        create(:contract_applied_invoice_custom_section, organization:, contract:)
      end

      it "returns the flat contract, without its rate cards nor its sections" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to eq(
          lago_id: contract.id,
          external_id: contract.external_id,
          lago_customer_id: customer.id,
          external_customer_id: customer.external_id,
          name: nil,
          plan_code: catalog_plan.code,
          status: "active",
          billing_time: "calendar",
          consolidate_invoice: true,
          purchase_order_number: nil,
          billing_anchor_date: nil,
          effective_billing_anchor_date: contract.effective_billing_anchor_date.iso8601,
          started_at: contract.started_at.iso8601(6),
          ended_at: nil,
          terminated_at: nil,
          canceled_at: nil,
          skip_invoice_custom_sections: false,
          created_at: contract.created_at.iso8601(6),
          updated_at: contract.updated_at.iso8601(6)
        )
      end
    end

    context "with dates and datetimes" do
      let(:params) { {status: "terminated"} }
      let(:contract) do
        create(
          :contract,
          :terminated,
          organization:,
          customer:,
          catalog_plan:,
          billing_anchor_date: Date.new(2026, 10, 5),
          started_at: Time.zone.parse("2026-10-01T08:30:00.123456Z"),
          terminated_at: Time.zone.parse("2026-10-20T17:45:00.654321Z")
        )
      end

      it "returns the datetimes to the microsecond and the dates as days" do
        subject

        expect(json[:contract]).to include(
          billing_anchor_date: "2026-10-05",
          effective_billing_anchor_date: "2026-10-05",
          started_at: "2026-10-01T08:30:00.123456Z",
          terminated_at: "2026-10-20T17:45:00.654321Z",
          created_at: contract.created_at.iso8601(6)
        )
      end
    end

    context "with expands[]=applied_rate_cards" do
      let(:params) { {expands: %w[applied_rate_cards]} }
      let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }

      # Ties to the microsecond, created out of order, next to cards that neither list may show.
      before do
        [1, 0, 2, 1, 0, 1].each { create(:contract_rate_card, organization:, contract:, created_at: created_at - it.seconds) }
        create(:contract_rate_card, organization:, contract:, created_at:).discard!
        create(:contract_rate_card, organization:, created_at:)
        sibling = create(:contract, :terminated, organization:, customer:, external_id: contract.external_id, started_at: 2.months.ago)
        create(:contract_rate_card, organization:, contract: sibling, created_at:)
      end

      def every_listed_applied_rate_card
        cards = []
        page_params = {limit: 2}

        while page_params
          get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards", page_params)
          cards.concat(json[:applied_rate_cards])
          page_params = json[:meta][:next_cursor]&.then { {limit: 2, after: it} }
        end

        cards
      end

      it "embeds every page of /applied_rate_cards, in its order" do
        listed = every_listed_applied_rate_card

        subject

        expect(listed.size).to eq(6)
        expect(json[:contract][:applied_rate_cards]).to eq(listed)
        expect(json[:contract].keys).to eq([*flat_keys, :applied_rate_cards])
      end
    end

    context "with expands[]=plan" do
      let(:params) { {expands: %w[plan]} }

      it "embeds the plan as its own show renders it" do
        subject
        expanded = json[:contract]
        get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}")

        expect(expanded[:plan]).to eq(json[:plan])
        expect(expanded[:plan]).to include(lago_id: catalog_plan.id, deleted_at: nil)
        expect(expanded.keys).to eq([*flat_keys, :plan])
      end

      context "when the plan is discarded" do
        before { catalog_plan.discard! }

        it "embeds it with its deleted_at" do
          subject

          expect(json[:contract][:plan]).to eq(V2::CatalogPlanSerializer.new(catalog_plan, includes: %i[usec_timestamps]).serialize)
          expect(json[:contract][:plan]).to include(lago_id: catalog_plan.id, deleted_at: catalog_plan.deleted_at.iso8601(6))
        end
      end

      context "without a plan" do
        let(:catalog_plan) { nil }

        it "renders it as null" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:contract]).to include(plan_code: nil, plan: nil)
        end
      end
    end

    context "with expands[]=customer" do
      let(:params) { {expands: %w[customer]} }

      # No v2 endpoint renders a customer of its own, so its serializer is the reference.
      it "embeds the flat customer" do
        subject

        expect(json[:contract][:customer]).to eq(V2::CustomerSerializer.new(customer, includes: %i[usec_timestamps]).serialize)
        expect(json[:contract][:customer]).to include(lago_id: customer.id, external_id: customer.external_id, deleted_at: nil)
        expect(json[:contract][:customer]).not_to include(:billing_configuration, :shipping_address, :metadata)
        expect(json[:contract].keys).to eq([*flat_keys, :customer])
      end

      context "when the customer is discarded" do
        before { customer.discard! }

        it "embeds it with its deleted_at" do
          subject

          expect(json[:contract][:customer]).to eq(V2::CustomerSerializer.new(customer, includes: %i[usec_timestamps]).serialize)
          expect(json[:contract][:customer]).to include(lago_id: customer.id, deleted_at: customer.deleted_at.iso8601(6))
        end
      end
    end

    context "with expands[]=invoice_custom_sections" do
      let(:params) { {expands: %w[invoice_custom_sections]} }

      # The selection of another contract, which the expansion leaves out.
      before { create(:contract_applied_invoice_custom_section, contract: create(:contract, organization:, customer:)) }

      it "renders an empty list without selected sections" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(invoice_custom_sections: [])
      end

      context "with selected sections" do
        let(:sections) { create_list(:invoice_custom_section, 3, organization:) }

        # Selected in another order than their creation: the second first, then the first and the third.
        before do
          {sections.second => 3, sections.first => 2, sections.third => 1}.each do |invoice_custom_section, minutes|
            create(:contract_applied_invoice_custom_section, contract:, invoice_custom_section:, created_at: minutes.minutes.ago)
          end
        end

        it "embeds the flat sections, the last selected first" do
          subject

          expect(json[:contract][:invoice_custom_sections]).to eq(
            [sections.third, sections.first, sections.second].map { V2::InvoiceCustomSectionSerializer.new(it, includes: %i[usec_timestamps]).serialize }
          )
          expect(json[:contract][:invoice_custom_sections]).to all(include(deleted_at: nil))
          expect(json[:contract][:invoice_custom_sections].first).to include(
            created_at: sections.third.created_at.iso8601(6),
            updated_at: sections.third.updated_at.iso8601(6)
          )
          expect(json[:contract].keys).to eq([*flat_keys, :invoice_custom_sections])
        end

        context "with a section deleted while the contract still selects it" do
          # Discarded directly: InvoiceCustomSections::DestroyService would delete the selection as well.
          before { sections.first.discard! }

          it "leaves it out" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:contract][:invoice_custom_sections].pluck(:lago_id)).to eq([sections.third.id, sections.second.id])
          end
        end
      end
    end

    context "with every expansion" do
      let(:params) { {expands: %w[invoice_custom_sections customer plan applied_rate_cards]} }

      # Cards with rate phases, so that reading them in the expansion would show as more queries.
      before do
        card = create(:contract_rate_card, organization:, contract:)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card)
        create(:contract_applied_invoice_custom_section, contract:)
      end

      it "embeds them after the contract, in the serializer's order" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract].keys).to eq([*flat_keys, :applied_rate_cards, :plan, :customer, :invoice_custom_sections])
      end

      context "with a contract of 3 cards, each with rate phases, and 3 sections" do
        let(:larger_contract) { create(:contract, organization:, customer:, catalog_plan:) }

        before do
          create_list(:contract_rate_card, 3, organization:, contract: larger_contract).each do |card|
            [1, 2].each { create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card, position: it) }
          end
          create_list(:contract_applied_invoice_custom_section, 3, contract: larger_contract)
        end

        def select_count(contract)
          statements = capture_sql { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", params) }
          statements.count { it.start_with?("SELECT") }
        end

        it "runs as many queries as for the contract of 1 card and 1 section" do
          # A first request can run lookups that the process then caches.
          select_count(contract)

          one_of_each = select_count(contract)
          larger = select_count(larger_contract)

          expect(response).to have_http_status(:success)
          expect(json[:contract].values_at(:applied_rate_cards, :invoice_custom_sections).map(&:size)).to eq([3, 3])
          expect(larger).to eq(one_of_each)
        end
      end
    end

    # /applied_rate_cards lists the cards of the live contract, while a status picks the contract to expand.
    context "with a status and expands[]=applied_rate_cards" do
      let(:params) { {status: "terminated", expands: %w[applied_rate_cards]} }
      let(:contract) { create(:contract, :terminated, organization:, customer:, started_at: 2.months.ago) }
      let(:live_contract) { create(:contract, organization:, customer:, external_id: contract.external_id) }
      let(:terminated_card) { create(:contract_rate_card, organization:, contract:) }
      let(:live_card) { create(:contract_rate_card, organization:, contract: live_contract) }

      before do
        terminated_card
        live_card
      end

      it "embeds the cards of the terminated contract, not those of the live one" do
        subject
        expanded = json[:contract]
        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards")

        expect(expanded).to include(lago_id: contract.id, status: "terminated")
        expect(expanded[:applied_rate_cards].pluck(:lago_id)).to eq([terminated_card.id])
        expect(json[:applied_rate_cards].pluck(:lago_id)).to eq([live_card.id])
      end
    end

    context "with an unknown expansion" do
      # The name under which the show embedded the sections before.
      let(:params) { {expands: %w[plan applied_invoice_custom_sections]} }

      it "returns an invalid expand error listing the allowed expansions" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          status: 400,
          error: "Bad Request",
          code: "invalid_expand",
          error_details: {
            expands: {
              invalid_values: %w[applied_invoice_custom_sections],
              allowed_values: %w[applied_rate_cards plan customer invoice_custom_sections]
            }
          }
        )
      end
    end

    context "with invoicing settings" do
      let(:contract) do
        create(:contract, organization:, customer:, catalog_plan:, consolidate_invoice: false, purchase_order_number: "PO-222")
      end

      it "returns the persisted settings" do
        subject

        expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-222")
      end
    end

    context "without a billing anchor" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-01")) }

      it "returns the start day as the effective anchor" do
        subject

        expect(json[:contract]).to include(billing_anchor_date: nil, effective_billing_anchor_date: "2026-10-01")
      end
    end

    context "when the external id contains a dot" do
      let(:contract) { create(:contract, organization:, customer:, external_id: "contract.2026-01") }

      it "matches the full id instead of truncating at the format separator" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:external_id]).to eq("contract.2026-01")
      end
    end

    context "with an unknown status filter value" do
      it "falls back to the active contract instead of raising on the enum cast" do
        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=bogus")

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when the contract is pending" do
      let!(:contract) { create(:contract, :pending, organization:, customer:) }

      it "returns it without a status filter" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
        expect(json[:contract][:status]).to eq("pending")
      end
    end

    context "when reading a terminated contract by status" do
      let!(:contract) { create(:contract, :terminated, organization:, customer:) }

      it "returns it only with an explicit status filter" do
        subject
        expect(response).to be_not_found_error("contract")

        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=terminated")
        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/contracts/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id" do
    subject { put_with_token(organization, "/api/v2/contracts/#{contract.external_id}", {contract: update_params}) }

    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }
    let(:update_params) { {name: "Renamed"} }

    include_examples "requires API permission", "contract", "write"

    it "updates the contract and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:name]).to eq("Renamed")
      expect(json[:contract].keys).to eq(flat_keys)
    end

    context "when skipping invoice custom sections" do
      let(:update_params) { {invoice_custom_section: {skip_invoice_custom_sections: true}} }

      before { create(:contract_applied_invoice_custom_section, organization:, contract:) }

      it "flags the contract and removes the attached sections" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:skip_invoice_custom_sections]).to be(true)
        expect(json[:contract].keys).to eq(flat_keys)
        expect(contract.reload.applied_invoice_custom_sections).to be_empty
      end
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:update_params) { {plan_code: other_plan.code} }
      let(:rate_card) { create(:rate_card, organization:) }

      before { create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card:, units: 4) }

      it "re-materializes the rate cards from the new plan, which a show then expands" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(plan_code: other_plan.code)
        expect(json[:contract].keys).to eq(flat_keys)

        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", {expands: %w[applied_rate_cards]})

        expect(json[:contract][:applied_rate_cards].sole[:rate_card_code]).to eq(rate_card.code)
      end
    end

    context "when the contract is already active" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

      it "updates the fields that stay editable" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:name]).to eq("Renamed")
      end

      context "with invoicing settings" do
        let(:update_params) { {consolidate_invoice: false, purchase_order_number: "PO-222"} }

        it "persists and returns both settings" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-222")
          expect(contract.reload).to have_attributes(consolidate_invoice: false, purchase_order_number: "PO-222")
        end

        context "when clearing the purchase order" do
          let(:contract) { create(:contract, organization:, customer:, catalog_plan:, purchase_order_number: "PO-111") }
          let(:update_params) { {purchase_order_number: nil} }

          it "clears the stored purchase order without changing consolidation" do
            subject

            expect(json[:contract]).to include(consolidate_invoice: true, purchase_order_number: nil)
            expect(contract.reload).to have_attributes(consolidate_invoice: true, purchase_order_number: nil)
          end
        end
      end

      context "when changing the plan" do
        let(:other_plan) { create(:catalog_plan, organization:) }
        let(:update_params) { {plan_code: other_plan.code} }

        it "returns an unprocessable entity error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:contract]).to eq(["contract_locked"])
        end
      end
    end

    context "when it does not exist" do
      subject { put_with_token(organization, "/api/v2/contracts/unknown", {contract: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "DELETE /api/v2/contracts/:external_id" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}") }

    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "write"

    it "terminates the active contract and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:status]).to eq("terminated")
      expect(json[:contract].keys).to eq(flat_keys)
    end

    context "when the contract is pending" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

      it "cancels it" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:status]).to eq("canceled")
      end
    end

    context "when a pending replacement coexists with the active contract" do
      it "terminates the active contract and leaves the replacement live" do
        replacement = create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: contract.external_id)

        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:status]).to eq("terminated")
        expect(replacement.reload.status).to eq("pending")
      end
    end

    context "when no live contract matches the external id" do
      subject { delete_with_token(organization, "/api/v2/contracts/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end
end
