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
    # Use the fallback CSS which is simpler and more reliable
    generate_fallback_css
  end
  
  private
  
  def generate_css_variables
    variables = @theme.css_variables.map do |var, value|
      "  #{var}: #{value};"
    end.join("\n")
    
    variables
  end
  
  def load_base_css
    base_css_path = Rails.root.join('app', 'assets', 'stylesheets', 'theme.css')
    
    if File.exist?(base_css_path)
      File.read(base_css_path)
    else
      # Fallback base CSS if file doesn't exist
      generate_fallback_css
    end
  end
  
  def generate_fallback_css
    <<~CSS
      /* Generated Theme CSS - Database-Driven Variables */
      [data-theme="#{@theme.name}"] {
        /* 21 Core Color Variables (Database-Driven) */
        #{generate_css_variables}
      }
      
      /* Fallback for when no theme is set */
      :root {
        /* Use default theme colors as fallback */
        #{generate_css_variables}
      }
      
      /* Spacing and Layout Variables (Static) */
      :root {
        --spacing-xs: 0.25rem;
        --spacing-sm: 0.5rem;
        --spacing-md: 1rem;
        --spacing-lg: 1.5rem;
        --spacing-xl: 2rem;
        
        --radius-sm: 0.25rem;
        --radius-md: 0.5rem;
        --radius-lg: 0.75rem;
        --radius-xl: 1rem;
        
        --shadow-sm: 0 1px 2px 0 var(--shadow-color);
        --shadow-md: 0 4px 6px -1px var(--shadow-color);
        --shadow-lg: 0 10px 15px -3px var(--shadow-color);
      }
      
      /* Basic styling */
      body {
        background-color: var(--primary-bg);
        color: var(--text-primary);
      }
      
      .card {
        background-color: var(--secondary-bg);
        border: 1px solid var(--border-color);
        border-radius: var(--radius-lg);
        box-shadow: var(--shadow-sm);
      }
      
      .btn-primary {
        background-color: var(--accent-color);
        border-color: var(--accent-color);
        color: var(--text-inverse);
      }
      
      .btn-primary:hover {
        background-color: var(--accent-hover);
        border-color: var(--accent-hover);
        color: var(--text-inverse);
      }
    CSS
  end
end 