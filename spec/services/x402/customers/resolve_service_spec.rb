# frozen_string_literal: true

require "rails_helper"

describe X402::Customers::ResolveService do
  subject(:result) { described_class.call(organization:, address:, family: :evm) }

  let(:organization) { create(:organization) }
  let(:address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }

  context "without a customer for the address" do
    it "creates the agent customer" do
      expect(result.customer).to have_attributes(
        organization:,
        external_id: "x402_0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
        x402_agent_address: address
      )
    end

    it "skips zero-amount invoices" do
      expect(result.customer).to be_finalize_zero_amount_invoice_skip
    end

    it "excludes the customer from dunning campaigns" do
      expect(result.customer).to be_exclude_from_dunning_campaign
    end

    context "with a tax integration in the organization" do
      before { create(:anrok_integration, organization:) }

      it "links no tax integration" do
        expect(result.customer.tax_customer).to be_nil
        expect(IntegrationCustomers::CreateJob).not_to have_been_enqueued
      end
    end
  end

  context "with a lowercase address" do
    let(:address) { "0xf4a43b9cc729c9e4e139cb86808f48e3ed09dcb2" }

    it "stores the checksummed address" do
      expect(result.customer.x402_agent_address).to eq("0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
    end

    it "derives the external id from the checksummed address" do
      expect(result.customer.external_id).to eq("x402_0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
    end
  end

  context "with a Solana address" do
    subject(:result) { described_class.call(organization:, address:, family: :svm) }

    let(:address) { "BprZ3eTVMHAcqC2wcE4XY71tvjdxJ6C6pSYjVmD75ujf" }

    it "stores the address verbatim" do
      expect(result.customer).to have_attributes(x402_agent_address: address, external_id: "x402_#{address}")
    end
  end

  context "with an address of another family" do
    let(:address) { "BprZ3eTVMHAcqC2wcE4XY71tvjdxJ6C6pSYjVmD75ujf" }

    it "raises" do
      expect { result }.to raise_error(ArgumentError, /invalid evm address/)
    end

    context "with a customer for the address" do
      before { create(:customer, organization:, x402_agent_address: address) }

      it "raises" do
        expect { result }.to raise_error(ArgumentError, /invalid evm address/)
      end
    end
  end

  context "with a customer for the address" do
    let(:customer) { create(:customer, organization:, x402_agent_address: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2") }

    before { customer }

    it "returns the customer" do
      expect(result.customer).to eq(customer)
    end

    it "creates no customer" do
      expect { result }.not_to change(Customer, :count)
    end

    context "with a lowercase address" do
      let(:address) { "0xf4a43b9cc729c9e4e139cb86808f48e3ed09dcb2" }

      it "returns the customer" do
        expect(result.customer).to eq(customer)
      end
    end
  end

  context "with a discarded customer for the address" do
    let(:discarded_customer) do
      create(:customer, organization:, external_id: "x402_#{address}", x402_agent_address: address, deleted_at: Time.current)
    end

    before { discarded_customer }

    it "creates a fresh customer" do
      expect(result.customer).to have_attributes(x402_agent_address: address, deleted_at: nil)
    end
  end

  context "with a customer for the address in another organization" do
    before { create(:customer, x402_agent_address: address) }

    it "creates a customer in the organization" do
      expect(result.customer.organization).to eq(organization)
    end
  end

  context "when a concurrent request creates the customer first" do
    before do
      customer
      lookups = 0
      allow(Customer).to receive(:by_x402_agent_address).and_wrap_original do |original, *args|
        lookups += 1
        (lookups == 1) ? Customer.none : original.call(*args)
      end
    end

    context "when the other insert has not committed" do
      let(:customer) { create(:customer, organization:, x402_agent_address: address) }

      it "returns the customer the other request created" do
        expect(result.customer).to eq(customer)
      end

      context "when the caller holds a transaction" do
        subject(:result) { ActiveRecord::Base.transaction { described_class.call(organization:, address:, family: :evm) } }

        it "returns the customer the other request created" do
          expect(result.customer).to eq(customer)
        end
      end
    end

    context "when the other insert has committed" do
      let(:customer) { create(:customer, organization:, external_id: "x402_#{address}", x402_agent_address: address) }

      it "returns the customer the other request created" do
        expect(result.customer).to eq(customer)
      end
    end

    context "when the re-read still misses" do
      let(:customer) { create(:customer, organization:, x402_agent_address: address) }

      before { allow(Customer).to receive(:by_x402_agent_address).and_return(Customer.none) }

      it "raises the unique violation" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  context "when the external id belongs to another customer" do
    before { create(:customer, organization:, external_id: "x402_#{address}") }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(external_id: ["value_already_exist"])
    end
  end

  context "when the create fails after the insert" do
    subject(:result) { ActiveRecord::Base.transaction { described_class.call(organization:, address:, family: :evm) } }

    let(:eu_tax_result) { Customers::EuAutoTaxesService::Result.new.tap { |eu_result| eu_result.tax_code = "lago_eu_missing" } }

    before { allow(Customers::EuAutoTaxesService).to receive(:call).and_return(eu_tax_result) }

    it "returns the failure" do
      expect(result.error.error_code).to eq("tax_not_found")
    end

    it "leaves no customer behind" do
      expect { result }.not_to change(Customer, :count)
    end
  end
end
