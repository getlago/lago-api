# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethod do
  subject { build(:payment_method) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:customer) }
  it { is_expected.to belong_to(:payment_provider_customer).class_name("PaymentProviderCustomers::BaseCustomer") }

  it { is_expected.to validate_presence_of(:provider_method_id) }
  it { is_expected.to validate_presence_of(:provider_method_type) }

  describe "validations" do
    describe "of only one default payment method" do
      subject(:payment_method) { build(:payment_method, customer:, is_default:) }

      let(:errors) { payment_method.errors.where(:is_default, :only_one_default_payment_method) }
      let(:customer) { create(:customer) }

      context "when is_default is true" do
        let(:is_default) { true }

        context "when a default payment method for the customer exists" do
          before do
            create(:payment_method, customer:, is_default:)
            subject
            payment_method.valid?
          end

          it "adds an error" do
            expect(errors).to be_present
          end
        end

        context "when no default payment method for the customer exists" do
          let(:is_default) { false }

          before do
            subject
            payment_method.valid?
          end

          it "does not add an error" do
            expect(errors).to be_blank
          end
        end
      end

      context "when is_default is false" do
        let(:is_default) { false }

        context "when a default payment method for the customer exists" do
          before do
            create(:payment_method, customer:, is_default:)
            subject
            payment_method.valid?
          end

          it "does not add an error" do
            expect(errors).to be_blank
          end
        end

        context "when no default payment method for the customer exists" do
          let(:is_default) { false }

          before do
            subject
            payment_method.valid?
          end

          it "does not add an error" do
            expect(errors).to be_blank
          end
        end
      end
    end
  end
end
