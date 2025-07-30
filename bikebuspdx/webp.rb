
module Bikebuspdx
  module Webp
    QUALITY = 85
    FLAGS = ""

    def self.compress(inpath, outpath)
      cmd = "cwebp -quiet -mt -q #{QUALITY.to_s} #{FLAGS} \"#{inpath}\" -o \"#{outpath}\""
      exit_code = 0
      error = ""
      output = ""
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close # we don't pass any input to the process
        output = stdout.gets
        error = stderr.gets
        exit_code = wait_thr.value
      end
      [exit_code, output, error]
    end

    def self.compress!(inpath, outpath)
      exit_code, output, error = compress(inpath, outpath)
      raise "cwebp for #{inpath} failed with code: #{exit_code}\n#{output}\n#{error}" if
        exit_code != 0
    end
  end
end
