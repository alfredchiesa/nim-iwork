# Changelog

## [1.3.0](https://github.com/alfredchiesa/nim-iwork/compare/v1.2.0...v1.3.0) (2026-10-26)


### Features

* adds better installation proc and new `iworkextract` ([2be48a1](https://github.com/alfredchiesa/nim-iwork/commit/2be48a1bb0e1528df8cbeaa2ba5287bd99da9091))
* extract rich text cells, keynote/pages tables, and grouped shapes ([16ba843](https://github.com/alfredchiesa/nim-iwork/commit/16ba8431fa4a0aaa6b7b31a27a7a09dac05d46d7))


### Bug Fixes

* adds wide cell offset coverage, fixes container and incomplete extraction bugs ([2a4fee3](https://github.com/alfredchiesa/nim-iwork/commit/2a4fee3aec625f1a3dbbc7e547ce8fee73b4b154))

## [1.2.0](https://github.com/alfredchiesa/nim-iwork/compare/v1.1.7...v1.2.0) (2026-08-29)


### Features

* new `getText()` helper method that returns all document text in reading order ([42bc754](https://github.com/alfredchiesa/nim-iwork/commit/42bc754737b825f03a818ba7fb5b4a35226be378))

## 1.1.7 (2026-07-24)


### Features

* container layer for zip, nested index.zip, and bundle documents ([62fc9a5](https://github.com/alfredchiesa/nim-iwork/commit/62fc9a54a94c26f156b2f7ed93c2d553c719e98f))
* iwa snappy chunk decoding plus iworkdump debug cli ([ddb1a33](https://github.com/alfredchiesa/nim-iwork/commit/ddb1a33f5fb99cd3211b75f5747c34854534eee9))
* numbers sheets, tables, and typed cell values ([ab9dd15](https://github.com/alfredchiesa/nim-iwork/commit/ab9dd15ffa90df42c0499adfbdea46923bc229a3))
* plain text extraction for all three document kinds ([b81939f](https://github.com/alfredchiesa/nim-iwork/commit/b81939f3b732a5a5754003da22d0af4f6729df34))
* protobuf wire decoder and full object index with reference resolution ([bdb9c8f](https://github.com/alfredchiesa/nim-iwork/commit/bdb9c8f65f8be5466062c02c2409e4db53f46caf))


### Bug Fixes

* ci and test docs ([3709ef5](https://github.com/alfredchiesa/nim-iwork/commit/3709ef5d2fbbb943964cc3210366ba0ab6a24a86))
* resolves broken ci/action ([c95c9bf](https://github.com/alfredchiesa/nim-iwork/commit/c95c9bf990ff7931a994b17812a2336a16a4122c))
