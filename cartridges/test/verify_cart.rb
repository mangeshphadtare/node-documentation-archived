#!/usr/bin/ruby

# Modules and Classes used to verify a OpenShift 2.0 Cartridge
#
# analogous to 'lint' for C code
#
require 'rubygems'
require 'fileutils'
require 'logger'
require 'test/unit'

# Create forward references
module Assertions
end
module Utils
end

# Count each severity of message logged.
class CountingFormatter < Logger::Formatter
  attr_accessor :counters

  def initialize
    super
    @counters = Hash.new(0)
  end

  def call(severity, time, progname, msg)
    @counters[severity] += 1
    super
  end
end

# Main class with business logic for verifying cartridges
class Runner
  attr_accessor :logger

  def initialize
    # Add expected cartridge files to given arrays for processing
    @required_bin  = %w(bin/setup bin/control)
    @required_file = %w(metadata/manifest.yml, ../.env)

    @optional_bin  = %w(bin/teardown bin/runhook bin/build)
    @optional_file = %w(metadata/locked_files.txt metadata/snapshot_exclusions.txt metadata/snapshot_transforms.txt
                        env)

    @logger           = Logger.new(STDERR)
    @logger.level     = Logger::DEBUG
    @logger.formatter = CountingFormatter.new
  end

  include Assertions
  include Utils
  include Test::Unit::Assertions

  # @param [String] cartridge_name
  # @return [Hash] Counters for each type of message logged
  def run(cartridge_name)
    cart_env = Hash.new("")

    # Step into the cartridge directory for these tests. Makes setup easier, shorter paths...
    FileUtils.chdir(cartridge_name) do

      # Ensure that required files exist
      [@required_bin, @required_file].flatten.each do |f|
        assert_required f
      end

      # Ensure that expected binaries are executable
      [@required_bin, @optional_bin].flatten.each do |f|
        assert_executable f if File.exist? f
      end

      # Emit warning if file is empty
      [@optional_bin, @optional_file].flatten.each do |f|
        assert_not_empty f if File.exist? f
      end

      render_env(load_env) # We need to do this to pretend to be the node platform
      cart_env = load_env # Now pick up any newly rendered environment variables
    end

    # Start with the 'setup' command just like node platform
    exitstatus, results = spawn_env(cart_env,"#{cartridge_name}/bin/setup --version=#{cartridge_name}")
    assert_equal(0, exitstatus, "setup results: #{results}")
    @logger.formatter.counters
  end
end

# Test and log common conditions
module Assertions
  def assert_executable(file)
    @logger.error { "Invalid mode on #{file}. Must be executable." } if not File.executable? file
  end

  def assert_not_empty(file)
    puts "#{file} #{File.stat(file).size}"
    @logger.warn ("#{file} is empty.") if 0 >= File.stat(file).size
  end

  def assert_required(file)
    return if File.exists?(file) && 0 < File.stat(file).size
    @logger.error ("Required file #{file} is missing or empty.")
  end
end

# Utilities used by business logic
module Utils
  def load_env
    env = {}
    Dir["env/*", "../.env/*"].each { |f|
      next if f.end_with?('.erb')

      contents = nil
      File.open(f) { |input|
        contents = input.read.chomp
        index    = contents.index('=')
        contents = contents[(index + 1)..-1]
        contents.gsub!(/\A["']|["']\Z/, '')
      }
      env[File.basename(f)] = contents
    }
    env
  end

  # @param [Hash] cart_env
  def render_env(cart_env)
    Dir["env/*"].each { |erb_file|
      next if not erb_file.end_with?('.erb')

      exitstatus, values = render_erb(cart_env, erb_file)
      @log.warn("erb file #{erb_file} contains too many lines. Expected 1 found #{values.size}") if 1 < values.size
      contents = values.first
      if 0 == exitstatus
        File.open(erb_file.gsub(/\.erb$/, ""), "w", 0444) { |env_file|
          env_file.write(contents)
        }
        File.delete(erb_file)
      end
    }
  end

  # @param [Hash] cart_env
  # @param [String] path
  def render_erb(cart_env, path)
    spawn_env(cart_env, "erb -S 2 -- #{path}")
  end

  def spawn_env(env, command)
    IO.pipe { |read_io, write_io|
      pid = spawn(env, command, {:unsetenv_others => true, :in => :close, :out => write_io})
      write_io.close
      results   = read_io.readlines()
      _, status = Process.waitpid2 pid, Process::WNOHANG
      [status.exitstatus, results]
    }
  end
end

# If we're being run as a script...
if __FILE__ == $0

  if ARGV.first.nil?
    $stderr.puts("Usage: #{File.basename($0)} <cartridge directory>")
    exit 1
  end

  runner  = Runner.new
  results = runner.run ARGV.first

  # Only provide summary of errors and warnings
  if  0 == results['ERROR'] && 0 == results['WARN']
    exit 0
  else
    $stderr.puts("\nErrors reported:   #{results['ERROR']}\nWarnings reported: #{results['WARN']}")
    exit 1
  end
end