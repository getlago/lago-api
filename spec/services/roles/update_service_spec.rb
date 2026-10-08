# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::UpdateService do
  include_context "with mocked security logger"

  describe "#call" do
    subject(:result) { described_class.call(role:, acting_membership:, params:) }

    let(:organization) { create(:organization) }
    let(:acting_membership) { create(:membership, organization:, roles: %i[admin]) }
    let(:role) { create(:role, organization:, code: "old_role", name: "Old Name", description: "Old description", permissions: %w[customers:view addons:view]) }
    let(:params) { {name: "New Name", description: "New description", permissions: %w[customers:view plans:view]} }

    context "when role exists" do
      it "updates the role" do
        expect { result }.to change { role.reload.name }.from("Old Name").to("New Name")
          .and change { role.reload.description }.from("Old description").to("New description")
      end

      it "returns success" do
        expect(result).to be_success
        expect(result.role).to eq(role)
      end

      it_behaves_like "produces a security log", "role.updated" do
        before { result }
      end

      context "with partial params" do
        let(:params) { {name: "New Name"} }

        it "updates only provided attributes" do
          expect { result }.to change { role.reload.name }.to("New Name")
            .and not_change { role.reload.description }
        end
      end

      context "with invalid params" do
        let(:params) { {name: ""} }

        it "does not update the role" do
          expect { result }.not_to change { role.reload.name }
        end

        it "returns validation error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end

        it_behaves_like "does not produce a security log" do
          before { result }
        end
      end
    end

    context "when the acting member is not an admin" do
      let(:acting_membership) { create(:membership, organization:, role: acting_role) }
      let(:acting_role) { create(:role, :custom, organization:, permissions: %w[roles:update customers:view customers:create]) }

      context "when adding a permission the member holds" do
        let(:params) { {permissions: %w[customers:view addons:view customers:create]} }

        it "updates the permissions" do
          expect { result }.to change { role.reload.permissions }.to(match_array(%w[customers:view addons:view customers:create]))
        end
      end

      context "when adding a permission the member does not hold" do
        let(:params) { {permissions: %w[customers:view addons:view plans:view]} }

        it "does not update the role" do
          expect { result }.not_to change { role.reload.permissions }
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

      context "when removing a permission the member does not hold" do
        let(:params) { {permissions: %w[customers:view]} }

        it "updates the permissions" do
          expect { result }.to change { role.reload.permissions }.to(%w[customers:view])
        end
      end

      context "when only renaming the role" do
        let(:params) { {name: "New Name"} }

        it "updates the role" do
          expect { result }.to change { role.reload.name }.to("New Name")
        end
      end
    end

    context "when role is nil" do
      let(:role) { nil }

      it "returns not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("role_not_found")
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "when role is predefined" do
      let(:role) { create(:role, :predefined, name: "Finance") }

      it "does not update the role" do
        expect { result }.not_to change { role.reload.name }
      end

      it "returns forbidden error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("predefined_role")
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "when name is changed and pending invites exist" do
      let(:other_role) { create(:role, organization:) }
      let!(:invite_with_role) { create(:invite, organization:, roles: [role.code], status: :pending) }
      let!(:invite_with_other_role) { create(:invite, organization:, roles: [other_role.code], status: :pending) }
      let!(:accepted_invite) { create(:invite, organization:, roles: [role.code], status: :accepted) }

      it "does not update pending invites when name changes (roles store codes)" do
        expect { result }.not_to change { invite_with_role.reload.roles }
      end

      it "does not update pending invites with other role codes" do
        expect { result }.not_to change { invite_with_other_role.reload.roles }
      end

      it "does not update accepted invites" do
        expect { result }.not_to change { accepted_invite.reload.roles }
      end
    end

    context "when name is not changed" do
      let(:params) { {description: "New description"} }
      let!(:invite_with_role) { create(:invite, organization:, roles: [role.code], status: :pending) }

      it "does not update invites" do
        expect { result }.not_to change { invite_with_role.reload.roles }
      end
    end
  end
end
