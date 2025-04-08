# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::ManageInvoiceCustomSectionsService do
  let(:customer) { create(:customer) }
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization: customer.organization) }
  let(:skip_invoice_custom_sections) { nil }
  let(:service) { described_class.new(customer: customer, section_ids:, skip_invoice_custom_sections:, section_codes:) }
  let(:section_ids) { nil }
  let(:section_codes) { nil }

  before do
    customer.selected_invoice_custom_sections << invoice_custom_sections[0] if customer
    customer.organization.selected_invoice_custom_sections = invoice_custom_sections[2..3] if customer
  end

  describe "#call" do
    context "when customer is not found" do
      let(:customer) { nil }

      it "returns not found failure" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("customer_not_found")
      end
    end

    context "when sending section_ids and section_codes together" do
      let(:invoice_custom_section) { create(:invoice_custom_section, organization: customer.organization) }
      let(:section_ids) { [invoice_custom_section.id] }
      let(:section_codes) { [invoice_custom_section.code] }

      it "raises an error" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.message).to include("section_ids_and_section_codes_sent_together")
      end
    end

    context "when sending section_ids" do
      context "when sending skip_invoice_custom_sections: true AND selected_ids" do
        let(:skip_invoice_custom_sections) { true }
        let(:section_ids) { [1, 2, 3] }

        it "raises an error" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.message).to include("skip_sections_and_selected_ids_sent_together")
        end
      end

      context "when updating selected_invoice_custom_sections" do
        context "when section_ids match customer's applicable sections" do
          let(:section_ids) { [invoice_custom_sections.first.id] }

          it "returns the result without changes" do
            result = service.call
            expect(result).to be_success
            expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
          end
        end

        context "when section_ids match organization's selected sections" do
          let(:section_ids) { invoice_custom_sections[2..3].map(&:id) }

          it "still sets selected invoice_custom_sections as custom" do
            service.call
            expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(invoice_custom_sections[2..3].map(&:id))
            expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
          end
        end

        context "when section_ids are totally custom" do
          let(:section_ids) { invoice_custom_sections[1..2].map(&:id) }

          it "assigns customer sections" do
            service.call
            expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(section_ids)
            expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
          end
        end

        context "when setting invoice_custom_sections_ids when previously customer had skip_invoice_custom_sections" do
          let(:section_ids) { [] }

          before { customer.update(skip_invoice_custom_sections: true) }

          it "sets skip_invoice_custom_sections to false" do
            service.call
            expect(customer.reload.skip_invoice_custom_sections).to be false
            expect(customer.selected_invoice_custom_sections.ids).to match_array([])
            expect(customer.applicable_invoice_custom_sections.ids).to match_array(customer.organization.selected_invoice_custom_sections.ids)
          end
        end
      end

      context "when an ActiveRecord::RecordInvalid error is raised" do
        let(:section_ids) { invoice_custom_sections[1..2].map(&:id) }

        before do
          allow(customer).to receive(:selected_invoice_custom_sections=).and_raise(ActiveRecord::RecordInvalid.new(customer))
        end

        it "returns record validation failure" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end
      end
    end

    context "when sending section_codes" do
      context "when sending skip_invoice_custom_sections: true AND selected_codes" do
        let(:skip_invoice_custom_sections) { true }
        let(:section_codes) { [] }

        it "raises an error" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.message).to include("skip_sections_and_selected_ids_sent_together")
        end
      end

      context "when updating selected_invoice_custom_sections" do
        context "when section_codes match customer's applicable sections" do
          let(:section_codes) { [invoice_custom_sections.first.code] }

          it "returns the result without changes" do
            result = service.call
            expect(result).to be_success
            expect(customer.applicable_invoice_custom_sections.map(&:code)).to match_array(section_codes)
          end
        end

        context "when section_ids are totally custom" do
          let(:section_codes) { invoice_custom_sections[1..2].map(&:code) }

          it "assigns customer sections" do
            service.call
            expect(customer.reload.selected_invoice_custom_sections.map(&:code)).to match_array(section_codes)
            expect(customer.applicable_invoice_custom_sections.map(&:code)).to match_array(section_codes)
          end
        end

        context "when setting invoice_custom_sections_ids when previously customer had skip_invoice_custom_sections" do
          let(:section_codes) { [] }

          before { customer.update(skip_invoice_custom_sections: true) }

          it "sets skip_invoice_custom_sections to false" do
            service.call
            expect(customer.reload.skip_invoice_custom_sections).to be false
            expect(customer.selected_invoice_custom_sections.ids).to match_array([])
            expect(customer.applicable_invoice_custom_sections.ids).to match_array(customer.organization.selected_invoice_custom_sections.ids)
          end
        end
      end
    end

    context "when updating customer to skip_invoice_custom_sections" do
      let(:skip_invoice_custom_sections) { true }

      before { customer.selected_invoice_custom_sections << invoice_custom_sections[1] }

      it "sets skip_invoice_custom_sections to true" do
        service.call
        expect(customer.reload.skip_invoice_custom_sections).to be true
        expect(customer.selected_invoice_custom_sections).to be_empty
        expect(customer.applicable_invoice_custom_sections).to be_empty
      end
    end

    context "when assigning section_ids and customer has system_generated sections" do
      let(:section_ids) { [invoice_custom_sections[0].id] }

      let!(:system_generated_section) do
        create(:invoice_custom_section, organization: customer.organization, section_type: :system_generated)
      end

      before do
        customer.system_generated_invoice_custom_sections << system_generated_section
      end

      it "keeps system_generated sections and adds selected manual ones" do
        service.call
        expect(customer.selected_invoice_custom_sections).to match_array([invoice_custom_sections[0], system_generated_section])
      end
    end

    context "when assigning section_codes and customer has system_generated sections" do
      let(:section_codes) { [invoice_custom_sections[1].code] }

      let!(:system_generated_section) do
        create(:invoice_custom_section, organization: customer.organization, section_type: :system_generated)
      end

      before do
        customer.system_generated_invoice_custom_sections << system_generated_section
      end

      it "keeps system_generated sections and adds selected manual ones" do
        service.call
        expect(customer.selected_invoice_custom_sections).to match_array([invoice_custom_sections[1], system_generated_section])
      end
    end

    context "when clearing all manual sections but customer has system_generated" do
      let(:section_ids) { [] }

      let!(:system_generated_section) do
        create(:invoice_custom_section, organization: customer.organization, section_type: :system_generated)
      end

      before do
        customer.selected_invoice_custom_sections << invoice_custom_sections[1]
        customer.system_generated_invoice_custom_sections << system_generated_section
      end

      it "removes manual but keeps system_generated sections" do
        service.call
        expect(customer.reload.manual_selected_invoice_custom_sections).to be_empty
        expect(customer.reload.selected_invoice_custom_sections).to match_array([system_generated_section])
      end
    end

    context "when an ActiveRecord::RecordInvalid error is raised" do
      let(:section_ids) { invoice_custom_sections[1..2].map(&:id) }

      before do
        allow(customer).to receive(:selected_invoice_custom_sections=).and_raise(ActiveRecord::RecordInvalid.new(customer))
      end

      it "returns record validation failure" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
