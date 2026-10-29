# frozen_string_literal: true

require "rails_helper"

describe X402::Invoices::SettleService do
  include_context "with an x402 payment"

  describe "#call" do
    subject(:result) { described_class.call(invoice:, payment:) }

    let(:customer) { create(:customer, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: "ab" * 32, x402_connection:)
    end
    let(:x402_evm_requirements) { super().merge("amount" => "1050000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "1050000"}}) }
    let(:payment) { x402_evm_payment }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:payee_address) { "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5" }
    let(:digest) do
      X402::Payments::ComputeDigestService.call(payment: x402_evm_payment, network: "eip155:84532", asset: x402_evm_requirements["asset"]).digest
    end
    let(:resource) { X402::Wire::V2Codec.invoice_resource(invoice) }
    let(:fault) { nil }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      create(:wallet, customer:, currency: "USD", x402_enabled: true)
      stub_cdp_facilitator(fault:)
    end

    def facilitator_request(path, payment, payment_requirements)
      a_request(:post, "#{cdp_facilitator_url}#{path}").with(body: {x402Version: 2, paymentPayload: payment, paymentRequirements: payment_requirements})
    end

    it "settles the attempt" do
      expect(result.settlement).to have_attributes(status: "settled", transaction_hash: "0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a")
    end

    it "settles with the facilitator" do
      result

      expect(facilitator_request("/settle", x402_evm_payment.merge("resource" => resource), x402_evm_requirements)).to have_been_made.once
    end

    it "pays the invoice" do
      result

      expect(invoice.reload.payment_status).to eq("succeeded")
    end

    it "verifies against the requirements built from the invoice" do
      result

      expect(facilitator_request("/verify", x402_evm_payment.merge("resource" => resource), x402_evm_requirements)).to have_been_made.once
    end

    context "with an accepted carrying other money terms" do
      let(:payment) { x402_evm_payment.merge("accepted" => x402_evm_requirements.merge("amount" => "1", "payTo" => "0x#{"22" * 20}")) }
      let(:reset_payment) { payment.merge("resource" => resource) }

      it "verifies against the requirements built from the invoice" do
        result

        expect(facilitator_request("/verify", reset_payment, x402_evm_requirements)).to have_been_made.once
      end
    end

    context "with another resource" do
      let(:payment) { x402_evm_payment.merge("resource" => {"url" => "https://example.com/listed"}) }
      let(:reset_payment) { x402_evm_payment.merge("resource" => resource) }

      it "settles the challenge's resource" do
        result

        expect(facilitator_request("/settle", reset_payment, x402_evm_requirements)).to have_been_made.once
      end

      context "with a bazaar extension" do
        let(:payment) do
          x402_evm_payment.merge(
            "resource" => {"url" => "https://example.com/listed"},
            "extensions" => {"bazaar" => {"info" => {}}, "other" => {"id" => 1}}
          )
        end
        let(:reset_payment) { x402_evm_payment.merge("resource" => resource, "extensions" => {"other" => {"id" => 1}}) }

        it "settles the challenge's envelope" do
          result

          expect(facilitator_request("/settle", reset_payment, x402_evm_requirements)).to have_been_made.once
        end

        it "stores the challenge's envelope" do
          expect(result.settlement.payload["payment"]).to eq(reset_payment)
        end
      end
    end

    context "with a payment that is not an object" do
      let(:payment) { nil }

      it "refuses it" do
        expect(result.error.messages).to eq({payment: ["invalid_payment"]})
      end
    end

    context "with an accepted that is not an object" do
      let(:payment) { x402_evm_payment.merge("accepted" => "eip155:84532") }

      it "refuses the network" do
        expect(result.error.messages).to eq({payment_requirements: ["unsupported_network"]})
      end
    end

    context "with a network the connection does not offer" do
      let(:payment) { x402_evm_payment.merge("accepted" => x402_evm_requirements.merge("network" => "eip155:8453")) }

      it "refuses the network" do
        expect(result.error.messages).to eq({payment_requirements: ["unsupported_network"]})
      end

      it "verifies nothing" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "with a resent payment that settled" do
      let(:settled) do
        create(:x402_settlement, :invoice_payment, x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:)
      end

      before { settled }

      it "answers the settled attempt" do
        expect(result.settlement).to eq(settled)
      end

      it "asks CDP nothing" do
        result

        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end

      it "logs the replay" do
        result

        expect(Rails.logger).to have_received(:info).with("X402::Invoices::SettleService replay status=settled network=eip155:84532")
      end

      context "with a voided invoice" do
        let(:invoice) do
          create(:invoice, :voided, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: "ab" * 32, x402_connection:)
        end

        it "still answers the settled attempt" do
          expect(result.settlement).to eq(settled)
        end
      end
    end

    context "with an authorization that is not valid UTF-8" do
      let(:payment) { x402_evm_payment.deep_merge("payload" => {"authorization" => {"from" => "0x\xFF".dup.force_encoding("UTF-8")}}) }

      it "refuses the payment" do
        expect(result.error.messages).to eq({payment: ["invalid_payment"]})
      end

      context "with a settled attempt awaiting its payment" do
        before { create(:x402_settlement, :invoice_payment, x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:) }

        it "answers that an attempt is pending" do
          expect(result.error.messages).to eq({base: ["invoice_payment_pending"]})
        end
      end
    end

    context "with a resent payment still pending" do
      before do
        create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:)
      end

      it "answers that an attempt is pending" do
        expect(result.error.messages).to eq({base: ["invoice_payment_pending"]})
      end

      it "verifies nothing" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "with a resent payment whose attempt failed" do
      let(:fault) { :verify_reject }

      before do
        create(:x402_settlement, :failed, :invoice_payment, x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:)
      end

      it "lets the facilitator decide" do
        expect(result.error.messages).to eq({payment: ["invalid_exact_evm_payload_signature"]})
      end
    end

    context "when the facilitator rejects the payment" do
      let(:fault) { :verify_reject }

      it "passes the reason on" do
        expect(result.error.messages).to eq({payment: ["invalid_exact_evm_payload_signature"]})
      end

      it "writes no attempt" do
        expect { result }.not_to change(X402::Settlement, :count)
      end
    end

    context "when the facilitator is unavailable" do
      before { stub_cdp_answer("/verify", status: 503, body: {errorType: "unavailable"}) }

      it "fails as a third-party error" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end

    context "with a payment for another amount" do
      let(:payment) { x402_evm_payment.deep_merge("payload" => {"authorization" => {"value" => "1000000"}}) }

      it "refuses it" do
        expect(result.error.messages).to eq({payment: ["amount_mismatch"]})
      end

      it "never settles" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when the payment is held in another organization" do
      before { create(:x402_settlement, :pending, payment_digest: digest) }

      it "refuses it" do
        expect(result.error.messages).to eq({base: ["payment_already_recorded"]})
      end

      it "never settles" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when another attempt wins the race" do
      before do
        allow(X402::Settlements::SettleService).to receive(:call).and_wrap_original do |original, **kwargs|
          create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payee_address:)
          original.call(**kwargs)
        end
      end

      it "answers that an attempt is pending" do
        expect(result.error.messages).to eq({base: ["invoice_payment_pending"]})
      end

      it "never settles" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when the same payment wins the race" do
      let(:racer) do
        create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:)
      end

      before do
        allow(X402::Settlements::SettleService).to receive(:call).and_wrap_original do |original, **kwargs|
          racer
          original.call(**kwargs)
        end
      end

      it "answers the pending attempt" do
        expect(result.settlement).to eq(racer)
      end

      it "never settles" do
        result

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when the pipeline refuses an invoice that has another attempt" do
      before do
        allow(X402::Settlements::SettleService).to receive(:call).and_wrap_original do |original, **kwargs|
          create(:x402_settlement, :invoice_payment, x402_connection:, invoice:, payee_address:)
          original.call(**kwargs)
        end
      end

      it "answers that an attempt is pending" do
        expect(result.error.messages).to eq({base: ["invoice_payment_pending"]})
      end

      it "fails the attempt" do
        result

        expect(X402::Settlement.find_by(payment_digest: digest)).to have_attributes(status: "failed", error_reason: "invoice_payment_pending")
      end
    end

    context "when the finish raises" do
      before do
        allow(X402::Invoices::FinishPaymentService).to receive(:call).and_raise(ActiveRecord::StatementInvalid)
      end

      it "answers the pending attempt" do
        expect(result.settlement).to have_attributes(status: "pending", transaction_hash: nil)
      end

      it "logs the failure" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "X402::Invoices::SettleService call failed reason=finish_failed network=eip155:84532 error=ActiveRecord::StatementInvalid"
        )
      end
    end

    context "when the link was rebound before the settle" do
      before do
        allow(X402::Settlements::SettleService).to receive(:call).and_return(
          X402::Settlements::SettleService::Result.new.single_validation_failure!(field: :invoice, error_code: "x402_connection_changed")
        )
      end

      it "answers as for an unknown link" do
        expect(result.error).to be_a(BaseService::NotFoundFailure).and have_attributes(resource: "invoice")
      end
    end

    context "with settlement_pending" do
      let(:fault) { :settlement_pending }

      it "answers the pending attempt" do
        expect(result.settlement).to have_attributes(status: "pending", transaction_hash: "0x#{"cd" * 32}")
      end

      it "leaves the invoice unpaid" do
        result

        expect(invoice.reload.payment_status).to eq("pending")
      end
    end

    context "with a Solana payment" do
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1, x402_payment_token: "ab" * 32, x402_connection:)
      end
      let(:x402_svm_requirements) { super().merge("amount" => "10000") }
      let(:payment) { x402_svm_payment }

      before do
        stub_cdp_supported(body: cdp_fixture("supported").sub("GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb", "D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM"))
        stub_cdp_answer("/verify", status: 200, body: {isValid: true, payer: x402_svm_payer})
      end

      it "verifies with the fee payer the transaction was built for" do
        result

        verify = a_request(:post, "#{cdp_facilitator_url}/verify").with do |request|
          JSON.parse(request.body).dig("paymentRequirements", "extra") == {"feePayer" => "GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb"}
        end

        expect(verify).to have_been_made.once
      end
    end
  end
end
