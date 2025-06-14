{
  description = "A reproducible development environment for the ebook2audiobook project.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        systemDeps = with pkgs; [
          calibre
          ffmpeg-full
          nodejs
          mecab
          espeak-ng
          rustc
          cargo
          sox
          tts
        ];

        # List of Python dependencies.
        pythonDeps = ps: with ps; [
          # Core ML and Data Science
          torch
          numpy
          pandas
          scipy
          pillow
          
          # TTS and ASR
          whisper

          # Web and API
          gradio
          requests
          beautifulsoup4
          
          # Utilities
          anyio
          charset-normalizer
          ebooklib
          einops
          encodec
          huggingface-hub
          inflect
          lxml
          pydantic
          pydub
          python-dotenv
          soupsieve
          tqdm
          transformers
          unidecode
        ];

        pythonEnv = pkgs.python312.withPackages pythonDeps;

        # --- GPU (CUDA) Specific Configuration ---
        cudaPkgs = pkgs.cudaPackages_12;

        pkgs-cuda = pkgs.extend (self: super: {
          python3 = super.python3.override {
            packageOverrides = python-self: python-super: {
              pytorch-bin = cudaPkgs.pytorch;
            };
          };
        });
        
        pythonEnv-cuda = pkgs-cuda.python312.withPackages pythonDeps;

      in
      {
        devShells = {
          default = pkgs.mkShell {
            name = "ebook2audiobook-cpu";
            buildInputs = [ pythonEnv ] ++ systemDeps;
            shellHook = ''
              echo "--- Ebook2Audiobook CPU Environment ---"
              echo "Run the application with: python app.py"
            '';
          };

          gpu = pkgs.mkShell {
            name = "ebook2audiobook-gpu";
            buildInputs = [ pythonEnv-cuda ] ++ systemDeps ++ [
              cudaPkgs.cudatoolkit
              cudaPkgs.cudnn
              cudaPkgs.nccl
            ];
            shellHook = ''
              echo "--- Ebook2Audiobook GPU Environment ---"
              echo "CUDA Toolkit and NVIDIA drivers are available."
              echo "Run the application with: python app.py --device gpu"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with cudaPkgs; [ cudatoolkit cudnn nccl ])}"
              export XLA_FLAGS=--xla_gpu_cuda_data_dir="${cudaPkgs.cudatoolkit}"
            '';
          };
        };
      });
}
