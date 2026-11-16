# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::UpdateService do
  subject(:update_service) { described_class.new(organization:, params:) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }

  let(:timezone) { nil }
  let(:email_settings) { [] }
  let(:invoice_grace_period) { 0 }
  let(:logo) { nil }
  let(:country) { "fr" }

  let(:params) do
    {
      legal_name: "Foobar",
      legal_number: "1234",
      tax_identification_number: "2246",
      email: "foo@bar.com",
      address_line1: "Line 1",
      address_line2: "Line 2",
      state: "Foobar",
      zipcode: "FOO1234",
      city: "Foobar",
      default_currency: "EUR",
      country:,
      timezone:,
      logo:,
      email_settings:,
      authentication_methods: ["email_password"],
      billing_configuration: {
        invoice_footer: "invoice footer",
        document_locale: "fr",
        invoice_grace_period:
      }
    }
  end

  describe "#call" do
    it "updates the organization" do
      result = update_service.call

      expect(result.organization.legal_name).to eq("Foobar")
      expect(result.organization.legal_number).to eq("1234")
      expect(result.organization.tax_identification_number).to eq("2246")
      expect(result.organization.email).to eq("foo@bar.com")
      expect(result.organization.address_line1).to eq("Line 1")
      expect(result.organization.address_line2).to eq("Line 2")
      expect(result.organization.state).to eq("Foobar")
      expect(result.organization.zipcode).to eq("FOO1234")
      expect(result.organization.city).to eq("Foobar")
      expect(result.organization.country).to eq("FR")
      expect(result.organization.default_currency).to eq("EUR")
      expect(result.organization.timezone).to eq("UTC")
      expect(result.organization.authentication_methods).to eq(["email_password"])

      expect(result.organization.invoice_footer).to eq("invoice footer")
      expect(result.organization.document_locale).to eq("fr")
    end

    context "with email containing unicode lookalike characters" do
      let(:params) { {email: "hello@something\u2013other.com"} }

      it "sanitizes the email before saving" do
        result = update_service.call
        expect(result.organization.email).to eq("hello@something-other.com")
      end
    end

    it "updates default billing_entity" do
      result = update_service.call

      default_billing_entity = result.organization.default_billing_entity
      expect(default_billing_entity.legal_name).to eq("Foobar")
      expect(default_billing_entity.legal_number).to eq("1234")
      expect(default_billing_entity.tax_identification_number).to eq("2246")
      expect(default_billing_entity.email).to eq("foo@bar.com")
      expect(default_billing_entity.address_line1).to eq("Line 1")
      expect(default_billing_entity.address_line2).to eq("Line 2")
      expect(default_billing_entity.state).to eq("Foobar")
      expect(default_billing_entity.zipcode).to eq("FOO1234")
      expect(default_billing_entity.city).to eq("Foobar")
      expect(default_billing_entity.country).to eq("FR")
      expect(default_billing_entity.default_currency).to eq("EUR")
      expect(default_billing_entity.timezone).to eq("UTC")

      expect(default_billing_entity.invoice_footer).to eq("invoice footer")
      expect(default_billing_entity.document_locale).to eq("fr")
    end

    context "when document_number_prefix is sent" do
      before { params[:document_number_prefix] = "abc" }

      it "converts document_number_prefix to upcase version" do
        result = update_service.call

        expect(result.organization.document_number_prefix).to eq("ABC")
      end
    end

    context "when finalize_zero_amount_invoice is sent" do
      before { params[:finalize_zero_amount_invoice] = "false" }

      it "converts document_number_prefix to upcase version" do
        result = update_service.call

        expect(result.organization.finalize_zero_amount_invoice).to eq(false)
      end
    end

    context "when document_url_expiration_days is sent" do
      before { params[:document_url_expiration_days] = 90 }

      it "updates the document url expiration window" do
        result = update_service.call

        expect(result.organization.document_url_expiration_days).to eq(90)
      end
    end

    context "when document_number_prefix is invalid" do
      before { params[:document_number_prefix] = "aaaaaaaaaaaaaaa" }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:document_number_prefix]).to eq(["value_is_too_long"])
      end
    end

    context "when customer_portal_locked_fields is null" do
      before { params[:customer_portal_locked_fields] = nil }

      it "returns a validation error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:customer_portal_locked_fields]).to eq(["value_is_mandatory"])
      end
    end

    context "when slug is sent" do
      before { params[:slug] = "new-slug" }

      it "updates the organization slug" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization.slug).to eq("new-slug")
      end
    end

    context "when slug has mixed case and whitespace" do
      before { params[:slug] = "  My-Slug  " }

      it "normalizes the slug before saving" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization.slug).to eq("my-slug")
      end
    end

    context "when slug is invalid" do
      before { params[:slug] = "INVALID SLUG!" }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:slug]).to be_present
      end
    end

    context "when slug is already taken" do
      before do
        create(:organization, slug: "taken-slug")
        params[:slug] = "taken-slug"
      end

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:slug]).to be_present
      end
    end

    context "when slug is a reserved word" do
      before { params[:slug] = "customers" }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:slug]).to be_present
      end
    end

    context "with premium features", :premium do
      let(:timezone) { "Europe/Paris" }
      let(:email_settings) { ["invoice.finalized"] }

      it "updates the organization" do
        result = update_service.call

        expect(result.organization.timezone).to eq("Europe/Paris")
      end

      context "when updating invoice grace period" do
        let(:customer) { create(:customer, organization:) }
        let(:invoice_grace_period) { 2 }

        let(:invoice_to_be_finalized) do
          create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("19 Jun 2022").to_date, organization:)
        end

        let(:invoice_to_not_be_finalized) do
          create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("21 Jun 2022").to_date, organization:)
        end

        before do
          invoice_to_be_finalized
          invoice_to_not_be_finalized
        end

        it "triggers async updates grace_period of invoices on default billing entity" do
          current_date = DateTime.parse("22 Jun 2022")
          old_invoice_grace_period = organization.invoice_grace_period

          travel_to(current_date) do
            result = update_service.call

            expect(result.organization.invoice_grace_period).to eq(2)
            expect(result.organization.default_billing_entity.invoice_grace_period).to eq(2)
            expect(Invoices::UpdateAllInvoiceIssuingDateFromBillingEntityJob)
              .to have_been_enqueued
              .with(
                organization.default_billing_entity,
                subscription_invoice_issuing_date_anchor: "next_period_start",
                subscription_invoice_issuing_date_adjustment: "align_with_finalization_date",
                invoice_grace_period: old_invoice_grace_period
              )
          end
        end
      end

      # Despite we do not use net_payment_term from org anymore, we need this test to ensure that update on billing_entity is
      # triggered and correctly handled
      # TODO: delete when cleaning up org from billing-entity specific data
      context "when updating net_payment_term" do
        let(:customer) { create(:customer, organization:) }

        let(:draft_invoice) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse("19 Jun 2022"), organization:)
        end

        let(:params) do
          {
            net_payment_term: 2
          }
        end

        before do
          draft_invoice
          organization.default_billing_entity.update!(
            net_payment_term: 30,
            payment_term: {"term_type" => "net", "days" => 30}
          )
        end

        it "persists the new term on the default billing entity without rewriting drafts" do
          current_date = DateTime.parse("22 Jun 2022")

          travel_to(current_date) do
            result = nil

            expect { result = update_service.call }
              .not_to change { draft_invoice.reload.attributes.slice("payment_term", "net_payment_term", "payment_due_date") }

            expect(result).to be_success
            expect(result.organization.net_payment_term).to eq(2)
            expect(result.organization.default_billing_entity.payment_term).to eq("term_type" => "net", "days" => 2)
          end
        end
      end
    end

    context "with base64 logo" do
      let(:logo) do
        logo_file = File.read(Rails.root.join("spec/factories/images/logo.png"))
        base64_logo = Base64.encode64(logo_file)

        "data:image/png;base64,#{base64_logo}"
      end

      it "updates the organization with logo" do
        result = update_service.call
        expect(result.organization.logo.blob).not_to be_nil
      end
    end

    context "with validation errors" do
      let(:country) { "---" }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:country]).to eq(["not_a_valid_country_code"])
      end
    end

    context "with eu tax management" do
      context "with org within the EU" do
        let(:params) { {eu_tax_management: true, country: "fr"} }

        before do
          allow(Taxes::AutoGenerateService).to receive(:call)
        end

        it "calls the taxes auto generate service" do
          result = update_service.call

          expect(result).to be_success
          expect(result.organization.eu_tax_management).to eq(true)
          expect(Taxes::AutoGenerateService).to have_received(:call).with(organization:).once
        end
      end

      context "with org outside the EU" do
        let(:params) { {eu_tax_management: true, country: "us"} }

        before do
          allow(Taxes::AutoGenerateService).to receive(:call)
        end

        it "does not call the taxes auto generate service" do
          result = update_service.call

          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({eu_tax_management: ["org_must_be_in_eu"]})
          expect(organization.reload.eu_tax_management).to eq(false)
          expect(Taxes::AutoGenerateService).not_to have_received(:call)
        end
      end

      context "with org is outside the EU but feature is already enabled" do
        let(:params) { {eu_tax_management: false} }

        before do
          organization.country = "us"
          organization.eu_tax_management = true
          allow(Taxes::AutoGenerateService).to receive(:call)
        end

        it "can disable eu_tax_management" do
          result = update_service.call

          expect(result).to be_success
          expect(result.organization.eu_tax_management).to eq(false)
          expect(Taxes::AutoGenerateService).not_to have_received(:call)
        end
      end
    end

    context "when organization does not have active billing_entities" do
      it "returns an error and does not update the organization" do
        organization.default_billing_entity.discard!
        organization.reload
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("billing_entity_not_found")
        expect(organization.reload.legal_name).not_to eq("Foobar")
        expect(organization.reload.legal_number).not_to eq("1234")
      end
    end

    context "when updating organization's document_numbering" do
      context "when updating to per_organization" do
        let(:params) { {document_numbering: "per_organization"} }

        it "updates the organization numbering to per_organization and default billing_entity to per_entity" do
          result = update_service.call

          expect(result.organization.document_numbering).to eq("per_organization")
          expect(result.organization.default_billing_entity.document_numbering).to eq("per_billing_entity")
        end
      end

      context "when updating to not existing value" do
        let(:params) { {document_numbering: "not_existing_document_numbering"} }

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:document_numbering]).to eq(["value_is_invalid"])
        end
      end
    end

    context "when authentication_methods change" do
      subject { described_class.new(organization:, params:, user:) }

      let(:params) { {authentication_methods: ["email_password", "okta"]} }
      let(:user) { create(:user) }
      let(:additions) { ["okta"] }
      let(:deletions) { ["google_oauth"] }

      before { create(:membership, organization:, roles: %i[admin], user:) }

      it "delivers a email notification" do
        expect { subject.call }.to have_enqueued_mail(OrganizationMailer, :authentication_methods_updated)
          .with(params: {organization:, user:, additions:, deletions:}, args: [])
      end

      it "produces a security log with the actor and the changed methods" do
        subject.call

        expect(security_logger).to have_received(:produce).with(
          organization:,
          log_type: "organization",
          log_event: "organization.authentication_methods_updated",
          user:,
          resources: {authentication_methods: {deleted: deletions, added: additions}}
        )
      end
    end

    context "when authentication_methods change but the update fails" do
      subject { described_class.new(organization:, params:, user:) }

      let(:params) { {authentication_methods: ["email_password", "okta"], email: "not-an-email"} }
      let(:user) { create(:user) }

      before { create(:membership, organization:, roles: %i[admin], user:) }

      it "does not persist the change, produce a security log nor send an email" do
        result = nil

        expect { result = subject.call }.not_to have_enqueued_mail(OrganizationMailer, :authentication_methods_updated)

        expect(result).not_to be_success
        expect(organization.reload.authentication_methods).to eq(%w[email_password google_oauth])
        expect(security_logger).not_to have_received(:produce)
          .with(hash_including(log_event: "organization.authentication_methods_updated"))
      end
    end

    context "when authentication_methods do not change" do
      let(:params) { {authentication_methods: organization.authentication_methods} }

      it "does not produce an authentication methods security log" do
        update_service.call

        expect(security_logger).not_to have_received(:produce)
          .with(hash_including(log_event: "organization.authentication_methods_updated"))
      end
    end

    context "with webhook_url" do
      let(:new_webhook_url) { "https://hooks.example.com/new" }
      let(:params) { {webhook_url: new_webhook_url} }
      let(:webhook_endpoint_logs) { hash_including(log_type: "webhook_endpoint") }

      context "when the organization has no webhook endpoint" do
        let(:organization) { create(:organization, webhook_url: nil) }

        it "creates the endpoint through the endpoint service" do
          organization.webhook_endpoints.load
          result = update_service.call

          expect(result).to be_success
          expect(organization.webhook_endpoints.reload.map { it.slice(:webhook_url, :signature_algo, :name, :event_types) })
            .to eq([{"webhook_url" => new_webhook_url, "signature_algo" => "jwt", "name" => nil, "event_types" => nil}])
          expect(result.organization.webhook_endpoints.map(&:webhook_url)).to eq([new_webhook_url])
          expect(security_logger).to have_received(:produce).with(
            organization:,
            log_type: "webhook_endpoint",
            log_event: "webhook_endpoint.created",
            resources: {webhook_url: new_webhook_url, signature_algo: "jwt"}
          )
        end

        it "enqueues the Segment job after commit" do
          expect { update_service.call }.to have_enqueued_job_after_commit(SegmentTrackJob)
            .with(hash_including(event: "webhook_endpoint_created"))
        end

        it "produces the security log only after commit" do
          ApplicationRecord.transaction do
            update_service.call

            expect(security_logger).not_to have_received(:produce).with(webhook_endpoint_logs)
          end

          expect(security_logger).to have_received(:produce).with(hash_including(log_event: "webhook_endpoint.created"))
        end

        context "with the standard_webhooks_signature flag" do
          before { organization.enable_feature_flag!(:standard_webhooks_signature) }

          it "creates a jwt endpoint with no signing key" do
            result = update_service.call

            expect(result).to be_success
            expect(organization.webhook_endpoints.reload.map(&:signature_algo)).to eq(["jwt"])
            expect(WebhookEndpointSigningKey.where(organization:)).to be_empty
          end
        end
      end

      context "when the lowest id endpoint signs with standard_webhooks" do
        let(:organization) { create(:organization, webhook_url: nil) }
        let(:target_webhook_endpoint) do
          create(:webhook_endpoint, id: "00000000-0000-4000-8000-000000000001", organization:, signature_algo: :standard_webhooks)
        end
        let(:other_webhook_endpoint) do
          create(:webhook_endpoint, id: "ffffffff-ffff-4fff-bfff-ffffffffffff", organization:, signature_algo: :standard_webhooks)
        end
        let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint: target_webhook_endpoint) }
        let(:other_signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint: other_webhook_endpoint) }

        before do
          organization.enable_feature_flag!(:standard_webhooks_signature)
          signing_key
          other_signing_key
        end

        it "changes only its url and keeps its algorithm and signing key" do
          other_attributes = other_webhook_endpoint.reload.attributes

          result = update_service.call

          expect(result).to be_success
          expect(target_webhook_endpoint.reload).to have_attributes(webhook_url: new_webhook_url, signature_algo: "standard_webhooks")
          expect(target_webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key.id])
          expect(other_webhook_endpoint.reload.attributes).to eq(other_attributes)
          expect(other_webhook_endpoint.signing_keys.pluck(:id)).to eq([other_signing_key.id])
        end
      end

      context "when the organization has several webhook endpoints" do
        let(:other_webhook_endpoint) { create(:webhook_endpoint, organization:) }
        let(:target_webhook_endpoint) { organization.webhook_endpoints.order(:id).first }
        let(:untouched_webhook_endpoint) { organization.webhook_endpoints.order(:id).last }
        let(:previous_url) { target_webhook_endpoint.webhook_url }
        let(:untouched_url) { untouched_webhook_endpoint.webhook_url }

        before do
          other_webhook_endpoint
          previous_url
          untouched_url
        end

        it "updates only the endpoint with the lowest id" do
          organization.webhook_endpoints.load
          result = update_service.call

          expect(result).to be_success
          expect(organization.webhook_endpoints.count).to eq(2)
          expect(target_webhook_endpoint.reload.webhook_url).to eq(new_webhook_url)
          expect(untouched_webhook_endpoint.reload.webhook_url).to eq(untouched_url)
          expect(result.organization.webhook_endpoints.map(&:webhook_url)).to match_array([new_webhook_url, untouched_url])
          expect(security_logger).to have_received(:produce).with(
            organization:,
            log_type: "webhook_endpoint",
            log_event: "webhook_endpoint.updated",
            # The diff of the url replaces the plain url in the resources.
            resources: {webhook_url: {deleted: previous_url, added: new_webhook_url}}
          )
        end

        it "produces the security log only after commit" do
          ApplicationRecord.transaction do
            update_service.call

            expect(security_logger).not_to have_received(:produce).with(webhook_endpoint_logs)
          end

          expect(security_logger).to have_received(:produce).with(hash_including(log_event: "webhook_endpoint.updated"))
        end
      end

      context "when the url is already set on the lowest id endpoint" do
        let(:new_webhook_url) { organization.webhook_endpoints.order(:id).first.webhook_url }

        it "does not update the endpoint nor produce a webhook endpoint security log" do
          webhook_endpoint = organization.webhook_endpoints.order(:id).first
          updated_at_before = webhook_endpoint.updated_at
          attributes_before = webhook_endpoint.attributes
          result = nil

          # Moves the clock so a write on the endpoint would change its updated_at.
          travel_to(1.hour.from_now) do
            expect { result = update_service.call }.not_to have_enqueued_job(SegmentTrackJob)
          end

          expect(result).to be_success
          expect(webhook_endpoint.reload.updated_at).to eq(updated_at_before)
          expect(webhook_endpoint.attributes).to eq(attributes_before)
          expect(organization.webhook_endpoints.pluck(:webhook_url)).to eq([new_webhook_url])
          expect(security_logger).not_to have_received(:produce).with(webhook_endpoint_logs)
        end
      end

      context "when the url is refused" do
        let(:params) { {webhook_url: new_webhook_url, name: "Renamed"} }

        before do
          stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => "false"))
          allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp("93.184.215.14", 0)])
        end

        shared_examples "a refused webhook url" do |expected_messages|
          it "returns the validation error and saves nothing" do
            endpoints_before = organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)
            name_before = organization.reload.name

            result = update_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to eq({webhook_url: expected_messages})
            expect(organization.reload.name).to eq(name_before)
            expect(organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)).to eq(endpoints_before)
            expect(security_logger).not_to have_received(:produce).with(webhook_endpoint_logs)
          end
        end

        shared_examples "refused webhook urls" do
          context "when the url is nil" do
            let(:new_webhook_url) { nil }

            it_behaves_like "a refused webhook url", %w[value_is_mandatory url_is_invalid]
          end

          context "when the url is blank" do
            let(:new_webhook_url) { "" }

            it_behaves_like "a refused webhook url", %w[value_is_mandatory url_is_invalid]
          end

          context "when the url is invalid" do
            let(:new_webhook_url) { "foobar" }

            it_behaves_like "a refused webhook url", %w[url_is_invalid]
          end

          context "when the url is a private address" do
            let(:new_webhook_url) { "http://169.254.169.254/latest/meta-data" }

            before { allow(Addrinfo).to receive(:getaddrinfo).and_call_original }

            it_behaves_like "a refused webhook url", %w[url_is_invalid]
          end
        end

        context "when the organization has no webhook endpoint" do
          let(:organization) { create(:organization, webhook_url: nil) }

          it_behaves_like "refused webhook urls"
        end

        context "when the organization has a webhook endpoint" do
          it_behaves_like "refused webhook urls"
        end

        # Only reachable on the update path: the other endpoint makes the organization have one.
        context "when the url belongs to another endpoint of the organization" do
          let(:organization) { create(:organization) }
          let(:new_webhook_url) { organization.webhook_endpoints.order(:id).last.webhook_url }

          before { create(:webhook_endpoint, organization:) }

          it_behaves_like "a refused webhook url", %w[value_already_exist]
        end
      end

      context "when another part of the update fails" do
        shared_examples "an update that fails elsewhere" do
          [
            ["an organization attribute is invalid", {email: "not-an-email"}],
            ["the billing entity update fails", {document_url_expiration_days: 365}]
          ].each do |description, failing_params|
            context "when #{description}" do
              let(:params) { {webhook_url: new_webhook_url, **failing_params} }

              it "leaves the endpoint unchanged and sends nothing" do
                endpoints_before = organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)
                result = nil

                expect { result = update_service.call }.not_to have_enqueued_job(SegmentTrackJob)

                expect(result).not_to be_success
                expect(organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)).to eq(endpoints_before)
                expect(security_logger).not_to have_received(:produce).with(webhook_endpoint_logs)
              end
            end
          end
        end

        context "when the organization has no webhook endpoint" do
          let(:organization) { create(:organization, webhook_url: nil) }

          it_behaves_like "an update that fails elsewhere"
        end

        context "when the organization has a webhook endpoint" do
          it_behaves_like "an update that fails elsewhere"
        end
      end
    end
  end
end
