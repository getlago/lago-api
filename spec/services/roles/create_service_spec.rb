# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::CreateService do
  include_context "with mocked security logger"

  describe "#call" do
    subject(:result) { described_class.call(organization:, acting_membership:, code:, name:, description:, permissions:) }

    let(:organization) { create(:organization) }
    let(:acting_membership) { create(:membership, organization:, roles: %i[admin]) }
    let(:code) { "custom_role" }
    let(:name) { "Custom Role" }
    let(:description) { "A custom role description" }
    let(:permissions) { %w[customers:view customers:create] }

    # Create the acting member and its roles outside the Role.count expectations
    before { acting_membership }

    context "with premium license and custom_roles integration", :premium do
      before { organization.update!(premium_integrations: ["custom_roles"]) }

      it "creates a new role" do
        expect { result }.to change(Role, :count).by(1)
      end

      it "returns success" do
        expect(result).to be_success
      end

      it "returns the created role" do
        expect(result.role).to have_attributes(
          organization_id: organization.id,
          name:,
          description:,
          permissions:
        )
      end

      it_behaves_like "produces a security log", "role.created" do
        before { result }
      end

      context "with invalid params" do
        let(:name) { nil }

        it "does not create a role" do
          expect { result }.not_to change(Role, :count)
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end

        it_behaves_like "does not produce a security log" do
          before { result }
        end
      end

      context "when the acting member is not an admin" do
        let(:acting_membership) { create(:membership, organization:, role: acting_role) }
        let(:acting_role) { create(:role, :custom, organization:, permissions: %w[roles:create customers:view]) }

        context "with permissions the member holds" do
          let(:permissions) { %w[customers:view] }

          it "creates the role" do
            expect { result }.to change(Role, :count).by(1)
          end
        end

        context "with a permission the member does not hold" do
          let(:permissions) { %w[customers:view customers:create] }

          it "does not create the role" do
            expect { result }.not_to change(Role, :count)
          end

          it "returns a forbidden error" do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ForbiddenFailure)
            expect(result.error.code).to eq("cannot_grant_permissions")
          end

          it_behaves_like "does not produce a security log" do
            before { result }
          end
        end
      end

      context "with reserved code" do
        let(:code) { "admin" }

        it "does not create a role" do
          expect { result }.not_to change(Role, :count)
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end
      end
    end

    context "with premium license but without custom_roles integration", :premium do
      before { organization.update!(premium_integrations: []) }

      it "does not create a role" do
        expect { result }.not_to change(Role, :count)
      end

      it "returns forbidden error with code" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("premium_integration_missing")
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "without premium license" do
      it "does not create a role" do
        expect { result }.not_to change(Role, :count)
      end

      it "returns forbidden error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end
  end
end
