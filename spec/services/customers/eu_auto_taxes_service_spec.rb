# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::EuAutoTaxesService do
  subject(:eu_tax_service) { described_class.new(customer:, new_record:, tax_attributes_changed:) }

  let(:organization) { create(:organization, country: "IT", eu_tax_management: true) }
  let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: true) }
  let(:customer) { create(:customer, organization:, billing_entity:, tax_identification_number:, zipcode: nil) }
  let(:new_record) { true }
  let(:tax_attributes_changed) { true }
  let(:tax_identification_number) { "IT12345678901" }

  shared_examples "a VIES check error" do |exception_class:, error_message:, error_type:|
    let(:full_error_message) { "The  web service returned the error: #{error_message}" }

    before do
      allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
        .and_raise(exception_class.new(error_message, nil))
      customer.update!(country: "DE")
    end

    it "returns an error" do
      result = eu_tax_service.call

      expect(result).not_to be_success
      expect(result.tax_code).to be_nil
      expect(result.error.code).to eq("vies_check_failed")
      expect(result.error.message).to eq("vies_check_failed: #{full_error_message}")

      expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
        valid: false,
        valid_format: true,
        error: full_error_message
      }).once
    end

    it "enqueues RetryViesCheckJob" do
      eu_tax_service.call

      expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(4.minutes.from_now..6.minutes.from_now).with(customer.id).once
    end

    it "creates a pending_vies_check record" do
      expect { eu_tax_service.call }.to change(PendingViesCheck, :count).by(1)

      pending_check = customer.pending_vies_check
      expect(pending_check).to have_attributes(
        organization: customer.organization,
        billing_entity: customer.billing_entity,
        tax_identification_number: customer.tax_identification_number,
        attempts_count: 1,
        last_error_type: error_type,
        last_error_message: full_error_message
      )
      expect(pending_check.last_attempt_at).to be_present
    end

    context "when pending_vies_check already exists" do
      let(:existing_check) { create(:pending_vies_check, customer:, attempts_count: 2, last_error_type: "unknown") }

      before { existing_check }

      it "updates the existing record and increments attempts_count" do
        expect { eu_tax_service.call }.not_to change(PendingViesCheck, :count)

        existing_check.reload
        expect(existing_check.attempts_count).to eq(3)
        expect(existing_check.last_error_type).to eq(error_type)
      end

      it "uses exponential backoff for retry delay" do
        eu_tax_service.call

        expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(9.minutes.from_now..11.minutes.from_now).with(customer.id)
      end
    end

    context "when pending_vies_check has many attempts" do
      let(:existing_check) { create(:pending_vies_check, customer:, attempts_count: 5, last_error_type: "unknown") }

      before { existing_check }

      it "caps retry delay at 1 hour" do
        eu_tax_service.call

        expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(59.minutes.from_now..61.minutes.from_now).with(customer.id)
      end
    end
  end

  describe ".call" do
    before do
      allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
    end

    context "with B2B organization" do
      let(:vies_response) { {} }

      context "when tax_identification_number is blank" do
        let(:tax_identification_number) { nil }

        before { customer.update!(country: "DE") }

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end

      context "when vat number is invalid" do
        let(:tax_identification_number) { "invalid_vat_number" }

        before do
          # No call to the API is made when the format is invalid
          allow_any_instance_of(Valvat).to receive(:exists?).and_call_original # rubocop:disable RSpec/AnyInstance
          customer.update!(country: "DE")
        end

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: false
          }).once
        end
      end

      context "when VIES check raises RateLimitError" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::RateLimitError,
          error_message: "rate limit reached",
          error_type: "rate_limit"
      end

      context "when VIES check raises MemberStateUnavailable error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::MemberStateUnavailable,
          error_message: "member state unavailable",
          error_type: "member_state_unavailable"
      end

      context "when VIES check raises ServiceUnavailable error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::ServiceUnavailable,
          error_message: "service unavailable",
          error_type: "service_unavailable"
      end

      context "when VIES check raises HTTPError with 307" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::HTTPError,
          error_message: "The VIES web service returned the error: 307 ",
          error_type: "service_unavailable"
      end

      context "when VIES check raises HTTPError without 307" do
        before do
          allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
            .and_raise(Valvat::HTTPError.new("The VIES web service returned the error: 301 ", nil))
          customer.update!(country: "DE")
        end

        it "re-raises the error" do
          expect { eu_tax_service.call }.to raise_error(Valvat::HTTPError, /301/)
        end
      end

      context "when VIES check raises Timeout error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::Timeout,
          error_message: "connection timed out",
          error_type: "timeout"
      end

      context "when VIES check raises BlockedError" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::BlockedError,
          error_message: "request blocked",
          error_type: "blocked"
      end

      context "when VIES check raises InvalidRequester error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::InvalidRequester,
          error_message: "invalid requester",
          error_type: "invalid_requester"
      end

      context "when eu_tax_management is false" do
        let(:organization) { create(:organization, country: "IT", eu_tax_management: false) }
        let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: false) }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "lago_eu_tax_exempt") }

        before { applied_tax }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are no eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "unknown_eu_tax_exempt") }
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        before { applied_tax }

        it "returns the billing_entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "with same country as the billing_entity" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        it "returns the organization country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end

        it "enqueues a SendWebhookJob" do
          eu_tax_service.call

          expect(SendWebhookJob).to have_been_enqueued
            .with("customer.vies_check", customer, vies_check: vies_response)
            .once
        end

        context "when a pending_vies_check exists from a previous failure" do
          let(:pending_check) { create(:pending_vies_check, customer:) }

          before { pending_check }

          it "deletes the pending_vies_check record" do
            expect { eu_tax_service.call }.to change(PendingViesCheck, :count).by(-1)
            expect(customer.reload.pending_vies_check).to be_nil
          end
        end
      end

      context "with a different country from the billing_entity one" do
        let(:vies_response) do
          {
            country_code: "DE"
          }
        end

        it "returns the reverse charge tax" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_reverse_charge")
        end
      end

      context "when country has exceptions" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        context "when customer has no zipcode" do
          it "returns the customer country standard tax" do
            result = eu_tax_service.call
            expect(result.tax_code).to eq("lago_eu_fr_standard")
          end
        end

        context "when customer has a zipcode" do
          context "when zipcode has applicable exceptions" do
            before do
              customer.update(country: "FR", zipcode: "97412")
            end

            it "returns the exception tax code" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_exception_reunion")
            end
          end

          context "when zipcode has no applicable exceptions" do
            before do
              customer.update(country: "FR", zipcode: "12345")
            end

            it "returns the customer counrty standard tax" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_standard")
            end
          end
        end
      end
    end

    context "with non B2B" do
      let(:vies_response) { false }

      context "when the customer has no country" do
        before do
          customer.update(country: nil)
        end

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "when the customer country is in europe" do
        before do
          customer.update(country: "DE")
        end

        it "returns the customer country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
        end
      end

      context "when the customer country is out of europe" do
        before do
          customer.update(country: "US")
        end

        it "returns the tax exempt tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_tax_exempt")
        end
      end
    end

    context "when customer is in a special territory" do
      let(:vies_response) { nil }

      shared_examples "a special territory tax assignment" do |country:, zipcode:, expected_tax_code:|
        before { customer.update(country:, zipcode:) }

        it "assigns #{expected_tax_code}" do
          result = eu_tax_service.call
          expect(result.tax_code).to eq(expected_tax_code)
        end
      end

      context "when B2B customer (non-France territories apply exception regardless)" do
        it_behaves_like "a special territory tax assignment",
          country: "ES", zipcode: "35001", expected_tax_code: "lago_eu_es_exception_canary_islands"
        it_behaves_like "a special territory tax assignment",
          country: "ES", zipcode: "38314", expected_tax_code: "lago_eu_es_exception_canary_islands"
        it_behaves_like "a special territory tax assignment",
          country: "ES", zipcode: "51001", expected_tax_code: "lago_eu_es_exception_ceuta"
        it_behaves_like "a special territory tax assignment",
          country: "ES", zipcode: "52001", expected_tax_code: "lago_eu_es_exception_melilla"
        it_behaves_like "a special territory tax assignment",
          country: "AT", zipcode: "6691", expected_tax_code: "lago_eu_at_exception_jungholz"
        it_behaves_like "a special territory tax assignment",
          country: "AT", zipcode: "6992", expected_tax_code: "lago_eu_at_exception_mittelberg"
        it_behaves_like "a special territory tax assignment",
          country: "AT", zipcode: "6991", expected_tax_code: "lago_eu_at_exception_mittelberg"
        it_behaves_like "a special territory tax assignment",
          country: "IT", zipcode: "23041", expected_tax_code: "lago_eu_it_exception_livigno"
        it_behaves_like "a special territory tax assignment",
          country: "IT", zipcode: "22061", expected_tax_code: "lago_eu_it_exception_campione_d_italia"
        it_behaves_like "a special territory tax assignment",
          country: "DE", zipcode: "78266", expected_tax_code: "lago_eu_de_exception_busingen_am_hochrhein"
        it_behaves_like "a special territory tax assignment",
          country: "DE", zipcode: "27498", expected_tax_code: "lago_eu_de_exception_heligoland"
        it_behaves_like "a special territory tax assignment",
          country: "PT", zipcode: "9500", expected_tax_code: "lago_eu_pt_exception_azores"
        it_behaves_like "a special territory tax assignment",
          country: "PT", zipcode: "9000", expected_tax_code: "lago_eu_pt_exception_madeira"
        it_behaves_like "a special territory tax assignment",
          country: "GR", zipcode: "63086", expected_tax_code: "lago_eu_gr_exception_mount_athos"
      end

      context "when B2C customer (non-France territories apply exception regardless)" do
        let(:tax_identification_number) { nil }

        it_behaves_like "a special territory tax assignment",
          country: "ES", zipcode: "35001", expected_tax_code: "lago_eu_es_exception_canary_islands"
        it_behaves_like "a special territory tax assignment",
          country: "AT", zipcode: "6691", expected_tax_code: "lago_eu_at_exception_jungholz"
        it_behaves_like "a special territory tax assignment",
          country: "IT", zipcode: "23041", expected_tax_code: "lago_eu_it_exception_livigno"
        it_behaves_like "a special territory tax assignment",
          country: "DE", zipcode: "78266", expected_tax_code: "lago_eu_de_exception_busingen_am_hochrhein"
        it_behaves_like "a special territory tax assignment",
          country: "PT", zipcode: "9500", expected_tax_code: "lago_eu_pt_exception_azores"
        it_behaves_like "a special territory tax assignment",
          country: "GR", zipcode: "63086", expected_tax_code: "lago_eu_gr_exception_mount_athos"
      end

      context "when B2B customer in France DOM-TOM (exception rate applies)" do
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97200", expected_tax_code: "lago_eu_fr_exception_martinique"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97100", expected_tax_code: "lago_eu_fr_exception_guadeloupe"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97412", expected_tax_code: "lago_eu_fr_exception_reunion"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97300", expected_tax_code: "lago_eu_fr_exception_guyane"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97600", expected_tax_code: "lago_eu_fr_exception_mayotte"
      end

      context "when B2C customer in France DOM-TOM (standard rate applies)" do
        let(:tax_identification_number) { nil }

        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97200", expected_tax_code: "lago_eu_fr_standard"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97100", expected_tax_code: "lago_eu_fr_standard"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97412", expected_tax_code: "lago_eu_fr_standard"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97300", expected_tax_code: "lago_eu_fr_standard"
        it_behaves_like "a special territory tax assignment",
          country: "FR", zipcode: "97600", expected_tax_code: "lago_eu_fr_standard"
      end

      context "when territory is detected" do
        before { customer.update(country: "ES", zipcode: "35001") }

        it "does not call VIES" do
          expect_any_instance_of(Valvat).not_to receive(:exists?) # rubocop:disable RSpec/AnyInstance
          eu_tax_service.call
        end

        it "does not send a webhook" do
          eu_tax_service.call
          expect(SendWebhookJob).not_to have_been_enqueued
        end

        context "when a pending VIES check exists" do
          before { create(:pending_vies_check, customer:) }

          it "destroys the pending VIES check" do
            expect { eu_tax_service.call }.to change(PendingViesCheck, :count).by(-1)
          end
        end
      end

      context "when zipcode contains spaces" do
        it "normalizes the zipcode before matching" do
          customer.update(country: "ES", zipcode: " 35 001 ")
          result = eu_tax_service.call
          expect(result.tax_code).to eq("lago_eu_es_exception_canary_islands")
        end
      end

      context "when customer relocates from mainland to special territory" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { true }
        let(:tax_identification_number) { nil }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "lago_eu_es_standard") }

        before do
          applied_tax
          customer.update(country: "ES", zipcode: "35001")
        end

        it "detects the territory and assigns the exception tax code" do
          result = eu_tax_service.call
          expect(result.tax_code).to eq("lago_eu_es_exception_canary_islands")
        end
      end

      context "when territory is not detected" do
        let(:tax_identification_number) { nil }
        let(:vies_response) { false }

        it "falls through when zipcode does not match any exception" do
          customer.update(country: "ES", zipcode: "28001")
          result = eu_tax_service.call
          expect(result.tax_code).to eq("lago_eu_es_standard")
        end

        it "falls through when customer has no zipcode" do
          customer.update(country: "DE")
          result = eu_tax_service.call
          expect(result.tax_code).to eq("lago_eu_de_standard")
        end

        it "falls through when customer has no country" do
          customer.update(country: nil, zipcode: "35001")
          result = eu_tax_service.call
          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end
    end
  end
end
