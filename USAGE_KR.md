# CAST 사용 가이드

CAST를 사용하여 대용량 과학 데이터베이스를 관리하는 방법에 대한 상세한 가이드입니다.

## 목차

- [시작하기](#시작하기)
- [기본 개념](#기본-개념)
- [단계별 튜토리얼](#단계별-튜토리얼)
- [실전 예제](#실전-예제)
- [고급 사용법](#고급-사용법)
- [문제 해결](#문제-해결)

## 시작하기

### 사전 요구사항

- Nix 패키지 매니저 (flakes 활성화)
- Git
- 대용량 데이터 저장을 위한 충분한 디스크 공간

### Nix Flakes 활성화

아직 활성화하지 않았다면:

```bash
# ~/.config/nix/nix.conf 또는 /etc/nix/nix.conf에 추가
experimental-features = nix-command flakes
```

### CAST 설치

프로젝트의 `flake.nix`에 CAST와 flake-parts를 입력으로 추가:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # CAST flakeModule import
      imports = [ inputs.cast.flakeModules.default ];

      # 여기에 설정 작성
    };
}
```

## 기본 개념

### CAST란 무엇인가?

CAST는 두 가지 주요 구성 요소로 이루어져 있습니다:

1. **콘텐츠 주소 지정 저장소 (CAS)**: BLAKE3 해시를 사용한 실제 데이터 파일
2. **Nix 파생 (Derivations)**: `/nix/store`의 메타데이터 및 심볼릭 링크

### 핵심 용어

- **데이터셋 (Dataset)**: 버전이 지정된 파일 모음
- **매니페스트 (Manifest)**: 데이터셋 메타데이터 및 파일 해시를 포함하는 JSON 파일
- **변환 (Transformation)**: 한 데이터셋을 다른 형식으로 변환하는 작업
- **저장소 경로 (Store Path)**: CAST가 실제 데이터를 저장하는 위치

### 데이터 흐름

```
로컬 파일
   ↓
cast put (해싱 및 저장)
   ↓
CAST 저장소 (/data/cast-store/store/{hash})
   ↓
매니페스트 생성 (manifest.json)
   ↓
mkDataset (Nix 파생 생성)
   ↓
/nix/store/{hash}-dataset/
   ├── manifest.json
   └── data/ (심볼릭 링크)
```

## 단계별 튜토리얼

### 1단계: 프로젝트 설정

새 프로젝트 디렉토리를 생성합니다:

```bash
mkdir my-database-project
cd my-database-project
```

기본 `flake.nix`를 생성합니다:

```nix
{
  description = "내 데이터베이스 프로젝트";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      # CAST flakeModule import
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # CAST 저장소 경로 설정
        cast.storePath = "/data/my-databases";

        packages = {
          # 여기에 데이터셋 추가 예정
        };
      };
    };
}
```

### 2단계: 저장소 디렉토리 생성

CAST 저장소용 디렉토리를 생성합니다:

```bash
# 저장소 디렉토리 생성
sudo mkdir -p /data/my-databases

# 소유권 설정
sudo chown $USER:$USER /data/my-databases

# 권한 설정
chmod 755 /data/my-databases
```

### 3단계: 첫 번째 데이터셋 추가

#### 3.1. 샘플 데이터 파일 생성

```bash
mkdir -p data
echo "안녕하세요, CAST!" > data/hello.txt
echo "데이터 내용" > data/info.txt
```

#### 3.2. 파일을 CAST 저장소에 추가

먼저 CAST CLI 도구를 빌드합니다:

```bash
nix build github:yourusername/cast#cast-cli
```

파일을 저장소에 추가합니다:

```bash
# cast-cli 사용
./result/bin/cast put data/hello.txt
# 출력: blake3:abc123...

./result/bin/cast put data/info.txt
# 출력: blake3:def456...
```

#### 3.3. 매니페스트 파일 생성

`manifests/my-first-dataset.json`을 생성합니다:

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "my-first-dataset",
    "version": "1.0.0",
    "description": "첫 번째 CAST 데이터셋"
  },
  "source": {
    "url": "file:///path/to/data",
    "download_date": "2024-01-15T10:00:00Z"
  },
  "contents": [
    {
      "path": "hello.txt",
      "hash": "blake3:abc123...",
      "size": 25,
      "executable": false
    },
    {
      "path": "info.txt",
      "hash": "blake3:def456...",
      "size": 20,
      "executable": false
    }
  ],
  "transformations": []
}
```

**참고**: `hash` 값을 `cast put` 명령의 실제 출력으로 교체하세요.

#### 3.4. flake.nix에 데이터셋 추가

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        cast.storePath = "/data/my-databases";

        packages = {
          my-first-dataset = castLib.mkDataset {
            name = "my-first-dataset";
            version = "1.0.0";
            manifest = ./manifests/my-first-dataset.json;
          };
        };
      };
    };
}
```

### 4단계: 데이터셋 빌드 및 사용

데이터셋을 빌드합니다:

```bash
nix build .#my-first-dataset
```

결과 확인:

```bash
# 심볼릭 링크 확인
ls -la result/

# 파일 내용 확인
cat result/data/hello.txt
cat result/data/info.txt

# 매니페스트 확인
cat result/manifest.json
```

### 5단계: 셸에서 데이터셋 사용

개발 셸을 설정합니다:

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { config, pkgs, castLib, ... }: {
        cast.storePath = "/data/my-databases";

        packages = {
          my-first-dataset = castLib.mkDataset {...};
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            config.packages.my-first-dataset
          ];

          shellHook = ''
            echo "데이터셋 경로: $CAST_DATASET_MY_FIRST_DATASET"
            echo "버전: $CAST_DATASET_MY_FIRST_DATASET_VERSION"
            ls -la $CAST_DATASET_MY_FIRST_DATASET
          '';
        };
      };
    };
}
```

셸에 진입:

```bash
nix develop

# 자동으로 환경 변수가 설정됩니다:
echo $CAST_DATASET_MY_FIRST_DATASET
cat $CAST_DATASET_MY_FIRST_DATASET/hello.txt
```

## 실전 예제

### 예제 1: NCBI BLAST 데이터베이스 관리

#### 단계 1: 데이터베이스 다운로드

```bash
# NCBI nr 데이터베이스 다운로드
wget ftp://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz

# 압축 해제
gunzip nr.gz
```

#### 단계 2: CAST에 추가

```bash
# CAST 저장소에 저장
nix run github:yourusername/cast#cast-cli -- put nr
# 출력: blake3:1234567890abcdef...
```

#### 단계 3: 매니페스트 생성

`manifests/ncbi-nr-2024-01.json`:

```json
{
  "schema_version": "1.0",
  "dataset": {
    "name": "ncbi-nr",
    "version": "2024-01-15",
    "description": "NCBI Non-Redundant Protein Database"
  },
  "source": {
    "url": "ftp://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz",
    "download_date": "2024-01-15T10:30:00Z",
    "server_mtime": "2024-01-14T18:00:00Z"
  },
  "contents": [
    {
      "path": "nr",
      "hash": "blake3:1234567890abcdef...",
      "size": 85000000000,
      "executable": false
    }
  ],
  "transformations": []
}
```

#### 단계 4: Nix에서 사용

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { config, pkgs, castLib, ... }: {
        cast.storePath = "/data/blast-databases";

        packages = {
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01-15";
            manifest = ./manifests/ncbi-nr-2024-01.json;
          };

          # BLAST 분석 파이프라인
          blast-analysis = pkgs.stdenv.mkDerivation {
            name = "blast-analysis";
            buildInputs = [
              pkgs.blast
              config.packages.ncbi-nr
            ];

            buildPhase = ''
              blastp \
                -query query.fasta \
                -db $CAST_DATASET_NCBI_NR/nr \
                -out results.txt \
                -outfmt 6
            '';
          };
        };
      };
    };
}
```

### 예제 2: 데이터베이스 변환 파이프라인

FASTA 데이터베이스를 여러 형식으로 변환:

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { config, pkgs, castLib, ... }: {
        cast.storePath = "/data/databases";

        packages = {
          # 원본 FASTA 데이터베이스
          ncbi-raw = castLib.mkDataset {
            name = "ncbi-nr-raw";
            version = "2024-01-15";
            manifest = ./ncbi-nr.json;
          };

          # MMseqs2 형식으로 변환
          ncbi-mmseqs = castLib.transform {
            name = "ncbi-nr-mmseqs";
            src = config.packages.ncbi-raw;

            builder = ''
              ${pkgs.mmseqs2}/bin/mmseqs createdb \
                "$SOURCE_DATA/nr" \
                "$CAST_OUTPUT/nr_mmseqs"

              ${pkgs.mmseqs2}/bin/mmseqs createindex \
                "$CAST_OUTPUT/nr_mmseqs" \
                /tmp/mmseqs_tmp
            '';
          };

          # BLAST 형식으로 변환
          ncbi-blast = castLib.transform {
            name = "ncbi-nr-blast";
            src = config.packages.ncbi-raw;

            builder = ''
              ${pkgs.blast}/bin/makeblastdb \
                -in "$SOURCE_DATA/nr" \
                -dbtype prot \
                -out "$CAST_OUTPUT/nr_blast" \
                -title "NCBI NR 2024-01"
            '';
          };

          # Diamond 형식으로 변환
          ncbi-diamond = castLib.transform {
            name = "ncbi-nr-diamond";
            src = config.packages.ncbi-raw;

            builder = ''
              ${pkgs.diamond}/bin/diamond makedb \
                --in "$SOURCE_DATA/nr" \
                --db "$CAST_OUTPUT/nr_diamond"
            '';
          };
        };

        # 모든 형식을 포함하는 개발 셸
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.mmseqs2
            pkgs.blast
            pkgs.diamond
            config.packages.ncbi-mmseqs
            config.packages.ncbi-blast
            config.packages.ncbi-diamond
          ];

          shellHook = ''
            echo "사용 가능한 데이터베이스:"
            echo "  MMseqs2: $CAST_DATASET_NCBI_NR_MMSEQS"
            echo "  BLAST:   $CAST_DATASET_NCBI_NR_BLAST"
            echo "  Diamond: $CAST_DATASET_NCBI_NR_DIAMOND"
          '';
        };
      };
    };
}
```

### 예제 3: 다중 버전 데이터베이스 레지스트리

여러 데이터베이스 버전 관리:

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { config, pkgs, castLib, ... }: {
        cast.storePath = "/data/lab-databases";

        packages = let
          # 버전별 NCBI NR 데이터셋
          ncbi-nr-versions = {
            "ncbi-nr-2024-01" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-01-15";
              manifest = ./manifests/ncbi-nr-2024-01.json;
            };
            "ncbi-nr-2024-02" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-02-01";
              manifest = ./manifests/ncbi-nr-2024-02.json;
            };
            "ncbi-nr-2024-03" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-03-01";
              manifest = ./manifests/ncbi-nr-2024-03.json;
            };
          };

          # 버전별 UniProt 데이터셋
          uniprot-versions = {
            "uniprot-2024-01" = castLib.mkDataset {
              name = "uniprot";
              version = "2024.01";
              manifest = ./manifests/uniprot-2024-01.json;
            };
          };
        in
          ncbi-nr-versions
          // uniprot-versions
          // {
            # 편의를 위한 별칭
            ncbi-nr-latest = ncbi-nr-versions."ncbi-nr-2024-03";
            ncbi-nr-stable = ncbi-nr-versions."ncbi-nr-2024-02";
            ncbi-nr-legacy = ncbi-nr-versions."ncbi-nr-2024-01";
            uniprot-latest = uniprot-versions."uniprot-2024-01";
          };

        # 다양한 환경을 위한 개발 셸
        devShells = {
          # 최신 버전 사용
          default = pkgs.mkShell {
            buildInputs = [
              config.packages.ncbi-nr-latest
              config.packages.uniprot-latest
            ];
          };

          # 레거시 분석 재현
          legacy = pkgs.mkShell {
            buildInputs = [
              config.packages.ncbi-nr-legacy
            ];
            shellHook = ''
              echo "레거시 환경 (2024-01)"
            '';
          };
        };
      };
    };
}
```

## 고급 사용법

### flake-parts와 CAST flakeModule 통합

CAST는 flake-parts 기반 flakeModule 패턴을 사용하여 간편한 설정을 제공합니다:

```nix
{
  description = "프로덕션 데이터베이스 레지스트리";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;

      # CAST flakeModule import
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = {config, pkgs, castLib, ...}: {
        # CAST 저장소 경로 설정
        cast.storePath = "/data/lab-databases";

        # castLib이 자동으로 주입됨
        packages = {
          # 주요 데이터베이스
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01-15";
            manifest = ./manifests/ncbi-nr.json;
          };

          uniprot = castLib.mkDataset {
            name = "uniprot";
            version = "2024.01";
            manifest = ./manifests/uniprot.json;
          };

          pfam = castLib.mkDataset {
            name = "pfam";
            version = "35.0";
            manifest = ./manifests/pfam.json;
          };

          # 변환: MMseqs2 형식
          ncbi-nr-mmseqs = castLib.transform {
            name = "ncbi-nr-mmseqs";
            src = config.packages.ncbi-nr;
            builder = ''
              ${pkgs.mmseqs2}/bin/mmseqs createdb \
                "$SOURCE_DATA/nr" \
                "$CAST_OUTPUT/nr"
            '';
          };
        };

        # 개발 셸
        devShells.default = pkgs.mkShell {
          buildInputs = [
            config.packages.ncbi-nr
            config.packages.uniprot
            config.packages.pfam
            pkgs.mmseqs2
            pkgs.blast
          ];

          shellHook = ''
            echo "=== 사용 가능한 데이터베이스 ==="
            echo "NCBI NR: $CAST_DATASET_NCBI_NR"
            echo "UniProt: $CAST_DATASET_UNIPROT"
            echo "Pfam:    $CAST_DATASET_PFAM"
            echo ""
            echo "저장소 위치: ${config.cast.storePath}"
          '';
        };

        # 앱: 데이터베이스 정보 표시
        apps.show-databases = {
          type = "app";
          program = "${pkgs.writeShellScript "show-dbs" ''
            echo "=== 데이터베이스 레지스트리 ==="
            ${pkgs.jq}/bin/jq . ${config.packages.ncbi-nr}/manifest.json
            ${pkgs.jq}/bin/jq . ${config.packages.uniprot}/manifest.json
          ''}";
        };
      };
    };
}
```

사용법:

```bash
# 데이터베이스 빌드
nix build .#ncbi-nr
nix build .#uniprot

# 개발 셸 진입
nix develop

# 데이터베이스 정보 표시
nix run .#show-databases
```

### 다중 계층 저장소

성능에 따라 다른 저장소 경로 사용 (개별 데이터셋별로 storePath 재정의):

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        # 기본 저장소 경로 (HDD)
        cast.storePath = "/mnt/hdd/cast-cold";

        packages = {
          # 자주 사용하는 최신 데이터베이스 (빠른 저장소로 재정의)
          ncbi-nr-latest = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-03-01";
            manifest = ./ncbi-nr-latest.json;
            storePath = "/mnt/nvme/cast-hot";  # 명시적 재정의
          };

          # 보관용 이전 버전 (기본 대용량 저장소 사용)
          ncbi-nr-2023 = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2023-12-01";
            manifest = ./ncbi-nr-2023.json;
            # storePath 생략 시 cast.storePath 사용
          };
        };
      };
    };
}
```

### 조건부 설정

환경에 따라 다른 설정 사용:

```nix
{
  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: let
        # CI 환경 확인
        isCI = builtins.getEnv "CI" == "true";
      in {
        # 환경별 저장소 경로 설정
        cast.storePath =
          if isCI
          then "/tmp/ci-databases"  # CI: 임시 디렉토리
          else "/data/production-databases";  # 프로덕션: 영구 저장소

        packages = {
          test-db = castLib.mkDataset {
            name = "test-db";
            version = "1.0.0";
            manifest = ./test-db.json;
          };
        };
      };
    };
}
```

### 공유 데이터베이스 레지스트리

여러 프로젝트에서 공유하는 데이터베이스 레지스트리:

**데이터베이스 레지스트리 (별도 저장소)**:

```nix
# databases/flake.nix
{
  description = "연구실 공유 데이터베이스 레지스트리";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast.url = "github:yourusername/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.cast.flakeModules.default ];

      perSystem = { castLib, ... }: {
        cast.storePath = "/data/shared-databases";

        packages = let
          ncbi-nr-versions = {
            "ncbi-nr-2024-01" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-01";
              manifest = ./manifests/ncbi-nr-2024-01.json;
            };
            "ncbi-nr-2024-02" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-02";
              manifest = ./manifests/ncbi-nr-2024-02.json;
            };
            "ncbi-nr-2024-03" = castLib.mkDataset {
              name = "ncbi-nr";
              version = "2024-03";
              manifest = ./manifests/ncbi-nr-2024-03.json;
            };
          };

          uniprot-versions = {
            "uniprot-2024-01" = castLib.mkDataset {
              name = "uniprot";
              version = "2024.01";
              manifest = ./manifests/uniprot-2024-01.json;
            };
            "uniprot-2024-02" = castLib.mkDataset {
              name = "uniprot";
              version = "2024.02";
              manifest = ./manifests/uniprot-2024-02.json;
            };
          };
        in
          ncbi-nr-versions
          // uniprot-versions
          // {
            # 편의를 위한 별칭
            ncbi-nr-latest = ncbi-nr-versions."ncbi-nr-2024-03";
            uniprot-latest = uniprot-versions."uniprot-2024-02";
          };
      };
    };
}
```

**사용자 프로젝트**:

```nix
# my-project/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    lab-databases.url = "git+ssh://lab-server/databases";
  };

  outputs = { self, nixpkgs, lab-databases }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.analysis = pkgs.stdenv.mkDerivation {
      name = "my-analysis";
      buildInputs = [
        lab-databases.packages.${system}.ncbi-nr-latest
        lab-databases.packages.${system}.uniprot-latest
        pkgs.mmseqs2
      ];

      buildPhase = ''
        # 공유 데이터베이스 사용
        mmseqs search \
          query.fasta \
          "$CAST_DATASET_NCBI_NR" \
          results.tsv
      '';
    };
  };
}
```

## 문제 해결

### 일반적인 오류

#### 1. "storePath not configured"

**오류**:
```
error: CAST storePath not configured.
```

**해결책**:
```nix
# CAST flakeModule import 및 cast.storePath 설정
{
  imports = [ inputs.cast.flakeModules.default ];

  perSystem = { castLib, ... }: {
    cast.storePath = "/data/cast";

    packages.my-dataset = castLib.mkDataset {...};
  };
}
```

#### 2. "Permission denied"

**오류**:
```
error: cannot create directory '/data/cast-store': Permission denied
```

**해결책**:
```bash
sudo mkdir -p /data/cast-store
sudo chown $USER:$USER /data/cast-store
chmod 755 /data/cast-store
```

#### 3. 환경 변수가 설정되지 않음

**문제**: `$CAST_DATASET_XXX`가 비어 있음

**해결책**: 데이터셋이 `buildInputs`에 있는지 확인:

```nix
pkgs.mkShell {
  buildInputs = [ myDataset ];  # ← 환경 변수에 필요
}
```

#### 4. 해시 불일치

**오류**:
```
error: hash mismatch in dataset 'ncbi-nr'
  specified: blake3:abc123...
  got:        blake3:def456...
```

**해결책**: 매니페스트의 해시 업데이트:

```bash
# 올바른 해시 얻기
nix run github:yourusername/cast#cast-cli -- put your-file

# manifest.json의 해시 값 업데이트
```

### 성능 최적화

#### 대용량 파일 처리

```bash
# 병렬 처리로 여러 파일 해싱
find data/ -type f | xargs -P 4 -I {} cast put {}
```

#### 저장소 공간 확인

```bash
# CAST 저장소 크기 확인
du -sh /data/cast-store

# 파일 수 확인
find /data/cast-store/store -type f | wc -l
```

### 디버깅 팁

#### 1. 매니페스트 검증

```bash
# JSON 구문 확인
jq . manifests/my-dataset.json

# 스키마 버전 확인
jq '.schema_version' manifests/my-dataset.json
```

#### 2. 심볼릭 링크 추적

```bash
# 데이터셋 빌드
nix build .#my-dataset

# 실제 파일 위치 확인
readlink -f result/data/myfile.txt

# CAST 저장소에 파일이 있는지 확인
ls -l /data/cast-store/store/ab/cd/abcd...
```

#### 3. 빌드 로그 확인

```bash
# 상세 로그와 함께 빌드
nix build .#my-dataset --print-build-logs

# 또는
nix build .#my-dataset -L
```

## 모범 사례

### 1. 버전 관리

```nix
# 날짜 기반 버전 사용
version = "2024-01-15";

# 또는 시맨틱 버전
version = "1.2.3";
```

### 2. 매니페스트 조직화

```
manifests/
├── ncbi/
│   ├── nr-2024-01.json
│   ├── nr-2024-02.json
│   └── nt-2024-01.json
├── uniprot/
│   ├── 2024.01.json
│   └── 2024.02.json
└── pfam/
    └── 35.0.json
```

### 3. 문서화

매니페스트에 명확한 설명 추가:

```json
{
  "dataset": {
    "name": "ncbi-nr",
    "version": "2024-01-15",
    "description": "NCBI Non-Redundant Protein Database, downloaded 2024-01-15. Contains all non-redundant GenBank CDS translations, PDB, SwissProt, PIR, and PRF sequences."
  }
}
```

### 4. 자동화

다운로드 및 매니페스트 생성 스크립트 작성:

```bash
#!/usr/bin/env bash
# update-ncbi-nr.sh

set -euo pipefail

VERSION=$(date +%Y-%m-%d)
URL="ftp://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz"

# 다운로드
wget "$URL" -O "nr-${VERSION}.gz"
gunzip "nr-${VERSION}.gz"

# CAST에 추가
HASH=$(nix run github:yourusername/cast#cast-cli -- put "nr-${VERSION}")

# 매니페스트 생성
cat > "manifests/ncbi-nr-${VERSION}.json" <<EOF
{
  "schema_version": "1.0",
  "dataset": {
    "name": "ncbi-nr",
    "version": "${VERSION}",
    "description": "NCBI Non-Redundant Protein Database"
  },
  "source": {
    "url": "${URL}",
    "download_date": "$(date -Iseconds)"
  },
  "contents": [
    {
      "path": "nr",
      "hash": "${HASH}",
      "size": $(stat -f%z "nr-${VERSION}"),
      "executable": false
    }
  ],
  "transformations": []
}
EOF

echo "매니페스트 생성됨: manifests/ncbi-nr-${VERSION}.json"
```

### 5. 백업

CAST 저장소 정기적 백업:

```bash
#!/usr/bin/env bash
# backup-cast-store.sh

BACKUP_DIR="/backup/cast-store-$(date +%Y%m%d)"

# 저장소 백업
rsync -av --progress /data/cast-store/ "$BACKUP_DIR/"

# 매니페스트도 백업
rsync -av --progress manifests/ "$BACKUP_DIR/manifests/"
```

## 추가 자료

- [README_KR.md](README_KR.md) - 프로젝트 개요 및 빠른 시작
- [CONFIGURATION.md](CONFIGURATION.md) - 상세 설정 가이드 (영문)
- [CLAUDE.md](CLAUDE.md) - 아키텍처 및 설계 결정 (영문)
- [examples/](examples/) - 실제 작동 예제

## 도움 받기

- 이슈 보고: https://github.com/yourusername/cast/issues
- 토론: https://github.com/yourusername/cast/discussions

---

즐거운 CAST 사용 되세요!
