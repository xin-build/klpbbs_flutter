/// Only a successful submission invalidates state reads that started earlier.
/// Reading an already-signed page does not invalidate a newer unsigned check.
class SignProofRevision {
  int _value = 0;

  int get value => _value;

  void recordSubmission({required bool success}) {
    if (success) _value++;
  }

  bool acceptsRead(int expected) => expected == _value;
}
