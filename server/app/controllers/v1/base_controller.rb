module V1
  class BaseController < ApplicationController
    include ApiSerialization

    before_action :ensure_current_workspace!

    private

    def current_workspace
      @current_workspace ||= Workspace.find_by!(
        slug: requested_workspace_slug
      )
    end

    def requested_workspace_slug
      request.headers["X-Workspace-Slug"].presence ||
        params[:workspace_slug].presence ||
        ENV.fetch("DEFAULT_WORKSPACE_SLUG", "default")
    end

    def ensure_current_workspace!
      current_workspace
    end
  end
end
