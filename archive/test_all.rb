#!/usr/bin/env ruby

# Test runner script for the Music Archive application
# Run with: ruby test_all.rb

require 'fileutils'
require 'time'

class TestRunner
  def initialize
    @results = []
    @start_time = Time.now
  end

  def run_all_tests
    puts "🎵 Music Archive Test Suite"
    puts "=" * 50
    puts "Starting tests at #{@start_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts

    # Run different test types
    run_model_tests
    run_controller_tests
    run_job_tests
    run_integration_tests

    # Print summary
    print_summary
  end

  private

  def run_model_tests
    puts "📋 Running Model Tests..."
    run_test_category("models") do
      system("bin/rails test test/models/")
    end
  end

  def run_controller_tests
    puts "🎮 Running Controller Tests..."
    run_test_category("controllers") do
      system("bin/rails test test/controllers/")
    end
  end

  def run_job_tests
    puts "⚡ Running Job Tests..."
    run_test_category("jobs") do
      system("bin/rails test test/jobs/")
    end
  end

  def run_integration_tests
    puts "🔗 Running Integration Tests..."
    run_test_category("integration") do
      system("bin/rails test test/integration/")
    end
  end

  def run_test_category(category)
    start_time = Time.now
    result = yield
    end_time = Time.now
    duration = end_time - start_time

    @results << {
      category: category,
      success: result,
      duration: duration,
      start_time: start_time,
      end_time: end_time
    }

    status = result ? "✅ PASSED" : "❌ FAILED"
    puts "   #{status} (#{duration.round(2)}s)"
    puts
  end

  def print_summary
    puts "📊 Test Summary"
    puts "=" * 50

    total_duration = Time.now - @start_time
    passed = @results.count { |r| r[:success] }
    failed = @results.count { |r| !r[:success] }

    @results.each do |result|
      status = result[:success] ? "✅" : "❌"
      duration = result[:duration].round(2)
      puts "#{status} #{result[:category].capitalize}: #{duration}s"
    end

    puts
    puts "Total: #{@results.length} test categories"
    puts "Passed: #{passed}"
    puts "Failed: #{failed}"
    puts "Duration: #{total_duration.round(2)}s"

    if failed > 0
      puts
      puts "❌ Some tests failed. Check the output above for details."
      exit 1
    else
      puts
      puts "🎉 All tests passed!"
    end
  end
end

# Run the tests
if __FILE__ == $0
  runner = TestRunner.new
  runner.run_all_tests
end 