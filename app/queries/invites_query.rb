# frozen_string_literal: true

class InvitesQuery < BaseQuery
  Result = BaseResult[:invites]
  Filters = BaseFilters[:role_ids]

  def call
    invites = base_scope

    invites = with_role_ids(invites) if filters.role_ids.present?

    invites = paginate(invites)
    invites = apply_consistent_ordering(invites)

    result.invites = invites
    result
  end

  private

  def base_scope
    scope = organization.invites.pending

    return scope if search_term.blank?

    scope.where("invites.email ILIKE ?", "%#{Invite.sanitize_sql_like(search_term)}%")
  end

  # Invites store role codes in an array column rather than referencing roles, so the
  # filtered ids are resolved to codes first. Codes are unique within an organization
  # scope, predefined ones being reserved, so the resolution is unambiguous.
  def with_role_ids(scope)
    codes = Role.with_organization(organization.id).where(id: filters.role_ids).pluck(:code)

    return scope.none if codes.empty?

    scope.where("invites.roles && ARRAY[?]::varchar[]", codes)
  end
end
