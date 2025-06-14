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

        # --- Custom Python Packages ---
        # m4b-util is not in nixpkgs, so we package it here.
        m4b-util = pkgs.python3Packages.buildPythonPackage rec {
          pname = "m4b-util";
          version = "2025.4.16";
          format = "pyproject";

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-RkX1Y6V1rYF+Hn71B8X3Z3XjK2n4k6iN9w8Z3p8Hn4g=";
          };

          # Dependencies needed to build and run m4b-util
          propagatedBuildInputs = with pkgs.python3Packages; [
            lark
            natsort
            rich
            poetry-core
          ];

          # The package has no tests to run
          doCheck = false;
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
          # --- Packages from your original flake ---
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
          pyopengl
          unidecode
          ray
          rich

          # --- Added to fix build errors ---
          pynvml # For 'nvidia-ml-py'
          translate
          bark # For 'suno-bark'
          sudachipy
          sudachidict-core
          unidic-lite # For 'unidic'

          # --- Add our custom-packaged m4b-util ---
          m4b-util
        ];

        pythonEnv = pkgs.python312.withPackages pythonDeps;

        # --- GPU (CUDA) Specific Configuration ---
        cudaPkgs = pkgs.cudaPackages_12;

        # Use an overlay to replace torch with the CUDA-enabled version
        cuda-overlay = final: prev: {
          python3 = prev.python3.override {
            packageOverrides = python-self: python-super: {
              torch = cudaPkgs.pytorch;
              # You can override other packages here if needed, e.g., torchvision
              torchvision = cudaPkgs.torchvision;
            };
          };
        };

        pkgs-cuda = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ cuda-overlay ];
        };
        
        pythonEnv-cuda = pkgs-cuda.python312.withPackages pythonDeps;

      in
      {
        devShells = {
          default = pkgs.mkShell {
            name = "ebook2audiobook-cpu";
            buildInputs = [ pythonEnv ] ++ systemDeps;
            shellHook = ''
              echo "--- Ebook2Audiobook CPU Environment ---"
              echo "All dependencies are provided by Nix."
              echo "Run the application directly with: python app.py"
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
              echo "All dependencies are provided by Nix."
              echo "Run the application directly with: python app.py --device gpu"

              # Set library paths for CUDA
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with cudaPkgs; [ cudatoolkit cudnn nccl ])}:${pkgs.stdenv.cc.cc.lib}/lib"
              export XLA_FLAGS=--xla_gpu_cuda_data_dir="${cudaPkgs.cudatoolkit}"
            '';
          };
        };
      });
}

