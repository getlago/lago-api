# frozen_string_literal: true

module ExpiredDocumentUrl
  EXPIRED_PAGE = <<~HTML.html_safe
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Link expired</title></head>
      <body><p>This link has expired.</p></body>
    </html>
  HTML

  private

  # Browsers get a plain page. API clients get a JSON error they can catch to fetch a fresh URL.
  def render_expired_document_url
    if request.headers["Accept"].to_s.include?("text/html")
      render html: EXPIRED_PAGE, status: :gone
    else
      render json: {status: 410, error: "Gone", code: "expired"}, status: :gone
    end
  end
end
