class ThemeCssGenerator
  def self.generate_for_theme(theme)
    new(theme).generate
  end

  def self.generate_all_themes
    Theme.active.map { |theme| generate_for_theme(theme) }
  end

  def initialize(theme)
    @theme = theme
  end

  def generate
    # Build CSS variables string
    variables = @theme.css_variables.map do |var, value|
      next unless value.present?
      "  #{var}: #{value};"
    end.compact.join("\n")

    # Read base CSS template
    base_css_path = Rails.root.join('app', 'assets', 'stylesheets', 'theme.css')
    
    if File.exist?(base_css_path)
      base_css = File.read(base_css_path)
    else
      base_css = default_base_css
    end

    # Generate theme-specific CSS
    css = <<~CSS
      /* Generated Theme CSS - Database-Driven Variables */
      [data-theme="#{@theme.name}"] {
      #{variables}
      }

      /* Fallback for when no theme is set */
      :root {
      /* Use default theme colors as fallback */
      }
    CSS

    # Combine with base CSS
    "#{css}\n\n#{base_css}"
  end

  private

  def default_base_css
    <<~CSS
      /* Default theme styles */
      body {
        background-color: var(--background-color, #ffffff);
        color: var(--text-color, #333333);
      }

      .navbar {
        background-color: var(--navbar-bg, #343a40) !important;
      }

      .card {
        background-color: var(--card-bg, #ffffff);
        border-color: var(--card-border, #dee2e6);
      }

      .btn-primary {
        background-color: var(--button-primary-bg, #007bff);
        border-color: var(--button-primary-bg, #007bff);
        color: var(--button-primary-text, #ffffff);
      }

      .btn-primary:hover {
        background-color: var(--button-primary-bg, #0056b3);
        border-color: var(--button-primary-bg, #0056b3);
      }

      .text-muted {
        color: var(--text-muted-color, #6c757d) !important;
      }

      .border {
        border-color: var(--border-color, #dee2e6) !important;
      }
    CSS
  end
end 