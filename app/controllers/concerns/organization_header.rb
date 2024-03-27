# frozen_string_literal: true

module OrganizationHeader
  def current_organization
    return unless organization_header
    return unless current_user

    @current_organization ||= current_user.organizations.find_by(id: organization_header)
  end

  def organization_header
    request.headers["x-lago-organization"]
  end
end
