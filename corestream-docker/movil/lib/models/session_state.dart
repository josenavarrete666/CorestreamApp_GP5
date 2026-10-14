import '../data/api_error.dart';
import 'api_models.dart';
import 'models.dart';

enum SessionPhase { restoring, signedOut, signingIn, passwordRequired, authenticated, signingOut, logoutPending }

class SessionState {
  const SessionState(this.phase, {this.user, this.profile, this.error, this.revocationConfirmed = false});
  final SessionPhase phase;
  final User? user;
  final ApiProfile? profile;
  final ApiError? error;
  final bool revocationConfirmed;
  bool get busy => {SessionPhase.restoring, SessionPhase.signingIn, SessionPhase.signingOut}.contains(phase);
}
