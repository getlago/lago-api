# frozen_string_literal: true

require "rails_helper"

describe X402::Settlement do
  subject(:settlement) { build(:x402_settlement) }

  describe "enums" do
    it do
      expect(settlement).to define_enum_for(:kind)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(credit_purchase: "credit_purchase", invoice_payment: "invoice_payment")
      expect(settlement).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", settled: "settled", failed: "failed")
      expect(settlement).to define_enum_for(:settled_by)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(lago: "lago", merchant: "merchant")
        .with_prefix
    end
  end

  describe "associations" do
    it do
      expect(settlement).to belong_to(:organization)
      expect(settlement).to belong_to(:x402_connection).class_name("X402::Connection").inverse_of(:settlements)
      expect(settlement).to belong_to(:customer).optional
      expect(settlement).to belong_to(:subscription).optional
      expect(settlement).to belong_to(:wallet_transaction).optional
      expect(settlement).to belong_to(:payment).optional.inverse_of(:x402_settlement)
      expect(settlement).to belong_to(:invoice).optional
    end
  end

  describe "soft deleted associations" do
    let(:organization) { create(:organization) }
    let(:connection) { create(:x402_connection, :discarded, organization:) }
    let(:customer) { create(:customer, organization:, deleted_at: Time.current) }
    let(:settlement) { create(:x402_settlement, organization:, x402_connection: connection, customer:) }

    it "still resolves a discarded connection" do
      expect(described_class.find(settlement.id).x402_connection).to eq(connection)
    end

    it "still resolves a discarded customer" do
      expect(described_class.find(settlement.id).customer).to eq(customer)
    end
  end

  describe "Scopes" do
    describe ".pending_reconciliation" do
      let!(:due) { create(:x402_settlement, :pending, reconcile_after: 1.minute.ago) }

      before do
        create(:x402_settlement, :pending, reconcile_after: 5.minutes.from_now)
        create(:x402_settlement, reconcile_after: 1.minute.ago)
      end

      it "returns pending rows whose reconcile_after has passed" do
        expect(described_class.pending_reconciliation).to eq([due])
      end
    end
  end

  describe "validations" do
    it do
      expect(settlement).to validate_presence_of(:asset)
      expect(settlement).to validate_presence_of(:payment_digest)
      expect(settlement).to validate_numericality_of(:settled_amount_atomic).only_integer.is_greater_than(0)
      expect(settlement).to validate_numericality_of(:settled_amount_cents).only_integer
    end

    describe "invoice validation" do
      subject(:settlement) { build(:x402_settlement, :invoice_payment, invoice: nil) }

      before { settlement.valid? }

      it { expect(settlement.errors.where(:invoice, :blank)).to be_present }
    end

    describe "purchase settings validation" do
      subject(:settlement) { build(:x402_settlement, purchase_settings:) }

      let(:purchase_settings) { nil }

      before { settlement.valid? }

      it { expect(settlement.errors.where(:purchase_settings, :blank)).to be_present }

      context "with empty purchase settings" do
        let(:purchase_settings) { {} }

        it { expect(settlement.errors.where(:purchase_settings, :blank)).to be_present }
      end

      context "with an invoice payment" do
        subject(:settlement) { build(:x402_settlement, :invoice_payment) }

        it { expect(settlement.errors.where(:purchase_settings)).to be_empty }
      end
    end

    describe "network validation" do
      subject(:settlement) { build(:x402_settlement, network: "eip155:1") }

      before { settlement.valid? }

      it "reports the network only" do
        expect(settlement.errors.attribute_names).to eq([:network])
      end

      it { expect(settlement.errors.messages[:network]).to eq(["value_is_invalid"]) }
    end

    describe "address validation" do
      subject(:settlement) { build(:x402_settlement, payer_address:, payee_address:) }

      let(:payer_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
      let(:payee_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }

      before { settlement.valid? }

      context "with a malformed EVM payer" do
        let(:payer_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d3" }

        it { expect(settlement.errors.messages[:payer_address]).to eq(["invalid_format"]) }
      end

      context "with an SVM payee on an EVM network" do
        let(:payee_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

        it { expect(settlement.errors.messages[:payee_address]).to eq(["invalid_format"]) }
      end

      context "with lowercase EVM addresses" do
        let(:payer_address) { "0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359" }
        let(:payee_address) { "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed" }

        it "stores both checksummed" do
          expect(settlement.errors).to be_empty
          expect([settlement.payer_address, settlement.payee_address])
            .to eq(["0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"])
        end
      end
    end

    describe "solana addresses" do
      subject(:settlement) { build(:x402_settlement, :solana) }

      before { settlement.valid? }

      it "stores them verbatim" do
        expect(settlement.errors).to be_empty
        expect(settlement.payer_address).to eq("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
      end
    end

    describe "connection validation" do
      let(:connection) { create(:x402_connection) }

      before { settlement.valid? }

      context "with a connection of another organization" do
        subject(:settlement) { build(:x402_settlement, x402_connection: connection, organization: other_organization) }

        let(:other_organization) { create(:organization) }

        it { expect(settlement.errors.messages[:x402_connection]).to eq(["must_belong_to_same_organization"]) }
      end

      context "with a network the connection does not offer" do
        subject(:settlement) do
          build(:x402_settlement, x402_connection: connection, network: "eip155:8453", asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913")
        end

        it { expect(settlement.errors.messages[:network]).to eq(["not_offered_by_connection"]) }
      end

      context "with a payee other than the connection's payout address" do
        subject(:settlement) { build(:x402_settlement, x402_connection: connection, payee_address: "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359") }

        it { expect(settlement.errors.messages[:payee_address]).to eq(["not_connection_payout_address"]) }
      end

      context "with another token than the connection's asset" do
        subject(:settlement) { build(:x402_settlement, x402_connection: connection, asset: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") }

        it { expect(settlement.errors.messages[:asset]).to eq(["not_connection_asset"]) }
      end

      context "with the connection's asset in lowercase" do
        subject(:settlement) { build(:x402_settlement, x402_connection: connection, asset: "0x036cbd53842c5426634e7929541ec2318f3dcf7e") }

        it "stores the checksummed asset" do
          expect(settlement.errors).to be_empty
          expect(settlement.asset).to eq("0x036CbD53842c5426634e7929541eC2318f3dCF7e")
        end
      end
    end

    describe "connection changes after creation" do
      let(:connection) { create(:x402_connection) }
      let(:settlement) { create(:x402_settlement, x402_connection: connection) }

      before { settlement }

      it "keeps an older row updatable after a payout rotation" do
        connection.update!(payout_addresses: {"evm" => "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"})

        expect(settlement.reload.update(status: "failed")).to be(true)
      end

      it "keeps an older row updatable after its network is removed" do
        connection.update!(networks: ["eip155:8453"])

        expect(settlement.reload.update(status: "failed")).to be(true)
      end
    end
  end

  describe "read-only attributes" do
    let(:settlement) { create(:x402_settlement) }

    it "refuses to rewrite a verified fact" do
      expect { settlement.payer_address = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { settlement.payee_address = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { settlement.payment_digest = "other" }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { settlement.purchase_settings = {} }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "updates the rest" do
      expect { settlement.update!(status: "failed", error_reason: "settle_timeout") }.not_to raise_error
    end
  end

  describe "check constraints" do
    subject(:insert) { settlement.save(validate: false) }

    let(:connection) { create(:x402_connection) }

    context "with a zero amount" do
      let(:settlement) { build(:x402_settlement, x402_connection: connection, settled_amount_atomic: 0) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_amount_positive/) }
    end

    context "with a settled row without a hash" do
      let(:settlement) { build(:x402_settlement, x402_connection: connection, transaction_hash: nil) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_settled_has_hash/) }
    end

    context "with a pending row without reconcile_after" do
      let(:settlement) { build(:x402_settlement, :pending, x402_connection: connection, reconcile_after: nil) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_pending_has_reconcile_after/) }
    end

    context "with an invoice payment without an invoice" do
      let(:settlement) { build(:x402_settlement, :invoice_payment, x402_connection: connection, invoice: nil) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_invoice_payment_has_invoice/) }
    end

    context "with a credit purchase without purchase settings" do
      let(:settlement) { build(:x402_settlement, x402_connection: connection, purchase_settings: nil) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_credit_purchase_has_settings/) }
    end

    context "with a merchant row that is still pending" do
      let(:settlement) { build(:x402_settlement, :pending, :merchant, x402_connection: connection) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_merchant_settled_credit_purchase/) }
    end

    context "with a merchant row on an invoice payment" do
      let(:settlement) { build(:x402_settlement, :invoice_payment, :merchant, x402_connection: connection) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_merchant_settled_credit_purchase/) }
    end

    context "with a merchant row that settled a credit purchase" do
      let(:settlement) { build(:x402_settlement, :merchant, x402_connection: connection) }

      it { expect(insert).to be(true) }
    end

    context "with a granted row without a subscription" do
      let(:settlement) { build(:x402_settlement, x402_connection: connection, wallet_transaction: create(:wallet_transaction), subscription: nil) }

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*check_x402_settlements_granted_has_subscription/) }
    end
  end

  describe "unique indexes" do
    subject(:insert) { duplicate.save(validate: false) }

    let(:organization) { create(:organization) }
    let(:connection) { create(:x402_connection, organization:) }

    describe "payment digest" do
      let(:duplicate) { build(:x402_settlement, :pending, organization:, x402_connection: connection, payment_digest: "digest") }

      context "when a settled attempt holds the digest" do
        before { create(:x402_settlement, organization:, x402_connection: connection, payment_digest: "digest") }

        it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_payment_digest/) }
      end

      context "when only a failed attempt holds the digest" do
        before { create(:x402_settlement, :failed, organization:, x402_connection: connection, payment_digest: "digest") }

        it { expect(insert).to be(true) }
      end

      context "when another organization holds the digest" do
        before { create(:x402_settlement, payment_digest: "digest") }

        it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_payment_digest/) }
      end
    end

    describe "pending credit purchase per payer" do
      let(:payer_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
      let(:duplicate) { build(:x402_settlement, :pending, organization:, x402_connection: connection, payer_address:) }

      context "when the payer has a pending credit purchase" do
        before { create(:x402_settlement, :pending, organization:, x402_connection: connection, payer_address:) }

        it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_pending_credit_purchase_payer/) }
      end

      context "when the payer has a pending invoice payment" do
        before { create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection: connection, payer_address:) }

        it { expect(insert).to be(true) }
      end

      context "when the payer's earlier purchase settled" do
        before { create(:x402_settlement, organization:, x402_connection: connection, payer_address:) }

        it { expect(insert).to be(true) }
      end
    end

    describe "payment" do
      let(:payment) { create(:payment) }
      let(:duplicate) { build(:x402_settlement, :invoice_payment, organization:, x402_connection: connection, payment:) }

      before { create(:x402_settlement, :invoice_payment, organization:, x402_connection: connection, payment:) }

      it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_payment_id/) }
    end

    describe "transaction hash" do
      let(:duplicate) { build(:x402_settlement, organization: duplicate_connection.organization, x402_connection: duplicate_connection, network:, transaction_hash: "0xabc") }
      let(:duplicate_connection) { connection }
      let(:network) { "eip155:84532" }

      before { create(:x402_settlement, organization:, x402_connection: connection, transaction_hash: "0xabc") }

      it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_network_and_transaction_hash/) }

      context "with another network" do
        let(:network) { "eip155:8453" }

        it { expect(insert).to be(true) }
      end

      context "with another organization" do
        let(:duplicate_connection) { create(:x402_connection) }

        it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_network_and_transaction_hash/) }
      end
    end

    describe "pending attempt per invoice" do
      let(:invoice) { create(:invoice, organization:) }
      let(:duplicate) { build(:x402_settlement, :invoice_payment, status, organization:, x402_connection: connection, invoice:) }
      let(:status) { :pending }

      before { create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection: connection, invoice:) }

      it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_pending_invoice_id/) }

      context "with a failed attempt" do
        let(:status) { :failed }

        it { expect(insert).to be(true) }
      end
    end
  end
end
