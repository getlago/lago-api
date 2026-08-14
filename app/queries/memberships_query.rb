# frozen_string_literal: true

class MembershipsQuery < BaseQuery
  Result = BaseResult[:memberships]
  Filters = BaseFilters[:role_ids]

  def call
    memberships = base_scope

    memberships = with_role_ids(memberships) if filters.role_ids.present?

    memberships = paginate(memberships)
    memberships = apply_consistent_ordering(memberships)

    result.memberships = memberships
    result
  end

  private

  def base_scope
    scope = organization.memberships.active

    return scope if search_term.blank?

    scope.where(user_id: matching_user_ids)
  end

  def matching_user_ids
    User.where("users.email ILIKE ?", "%#{User.sanitize_sql_like(search_term)}%").select(:id)
  end

  def with_role_ids(scope)
    scope.where(id: MembershipRole.joins(:role).where(organization:, role_id: filters.role_ids).select(:membership_id))
  end
end
