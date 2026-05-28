import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';

abstract interface class BoardRepository {
  Future<Result<BoardSnapshot, AppFailure>> load(
    String projectId,
    String milestoneId,
  );
}
