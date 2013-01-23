#--
# Copyright 2013 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++


module OpenShift

  # Class represents the Ruby analogy of C environ(7)
  class Environ

    def self.for_gear(home_dir)
      load(File.join(home_dir, '*/env/*')) + load(File.join(home_dir, '.env/*'))
    end

    # Read a Gear's + n number cartridge environment variables into a environ(7) hash
    # @param [String]               env_dir of gear to be read
    # @return [Hash<String,String>] environment variable name: value
    def self.load(env_dir)
      env = {}

      # Find and read environment variables for gear and cartridges into a hash
      Dir[env_dir].each { |file|
        next if file.end_with?('.erb')
        next if File.directory? file

        contents = nil
        File.open(file) { |input|
          contents = input.read.chomp
          index    = contents.index('=')
          contents = contents[(index + 1)..-1]
          contents.gsub!(/\A["']|["']\Z/, '')
        }
        env[File.basename(file)] = contents
      }
      env
    end
  end
end