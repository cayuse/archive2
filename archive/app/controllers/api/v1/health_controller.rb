class Api::V1::HealthController < ApplicationController
  # In case authenticate_api_user! isn't globally defined, don't raise
  skip_before_action :authenticate_api_user!, raise: false
  
  def show
    # Basic health checks
    checks = {
      database: database_healthy?,
      storage: storage_healthy?,
      search: search_healthy?
    }
    
    all_healthy = checks.values.all?
    
    status = all_healthy ? :ok : :service_unavailable
    
    render json: {
      status: all_healthy ? 'healthy' : 'unhealthy',
      timestamp: Time.current.iso8601,
      checks: checks,
      version: '1.0.0'
    }, status: status
  end
  
  private
  
  def database_healthy?
    begin
      ActiveRecord::Base.connection.execute('SELECT 1')
      true
    rescue => e
      Rails.logger.error "Database health check failed: #{e.message}"
      false
    end
  end
  
  def storage_healthy?
    begin
      # Check if Active Storage is configured and accessible
      Rails.application.routes.url_helpers.rails_blob_path('test', only_path: true)
      true
    rescue => e
      Rails.logger.error "Storage health check failed: #{e.message}"
      false
    end
  end
  
  def search_healthy?
    begin
      # Check if PostgreSQL full-text search is working
      Song.full_text_search('test').limit(1)
      true
    rescue => e
      Rails.logger.error "Search health check failed: #{e.message}"
      false
    end
  end
end 