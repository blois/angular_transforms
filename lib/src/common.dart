library angular_transformers.common;

import 'package:analyzer/src/generated/ast.dart';
import 'package:source_maps/refactor.dart';
import 'package:barback/barback.dart';

/**
 * Transforms all simple identifiers of [name] to be [replacement].
 */
void transformIdentifiers(TextEditTransaction transaction, CompilationUnit unit,
    String name, String replacement) {
  unit.accept(new _IdentifierTransformer(transaction, name, replacement));
}

/**
 * Injects an import into the list of imports in the file.
 */
void addImport(TextEditTransaction transaction, CompilationUnit unit,
    String uri, String alias) {
  var libDirective;
  for (var directive in unit.directives) {
    if (directive is ImportDirective) {
      transaction.edit(directive.keyword.offset, directive.keyword.offset,
          'import "$uri" as $alias;\n');
      return;
    } else if (directive is LibraryDirective) {
      libDirective = directive;
    }
  }

  // No imports, add after the library directive if there was one.
  if (libDirective != null) {
    transaction.edit(libDirective.endToken.offset + 2,
        libDirective.endToken.offset + 2,
        'import "$uri" as $alias;\n');
  }
}

class _IdentifierTransformer extends GeneralizingASTVisitor {
  final TextEditTransaction transaction;
  final String name;
  final String replacement;

  _IdentifierTransformer(this.transaction, this.name, this.replacement);

  visitNode(ASTNode node) {
    if (node is SimpleIdentifier && node.name == name) {
      transaction.edit(node.offset, node.end, replacement);
    }
    return super.visitNode(node);
  }
}

bool canImportAsset(AssetId id) => id.path.startsWith('lib/');
