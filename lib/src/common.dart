library angular_transformers.common;

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:source_maps/refactor.dart';
import 'package:barback/barback.dart';
import 'resolver.dart';


/**
 * Transforms all simple identifiers of [identifier] to be [replacement] in the
 * entry point of the application.
 *
 * This will resolve the full name of [identifier] and warn if it cannot be
 * resolved.
 *
 * If the identifier is found and modifications are made then an import will be
 * added to the file indicated by [generatedFilename].
 */
void transformIdentifiers(Transform transform, Resolver resolver,
    {String identifier, String replacement, String generatedFilename,
    String importPrefix}) {

  var identifierElement = resolver.getLibraryVariable(identifier);

  if (identifierElement == null) {
    transform.logger.info('Unable to resolve $identifier, not '
        'transforming entry point.');
    transform.addOutput(transform.primaryInput);
    return;
  }

  var lib = resolver.entryLibrary;
  var id = transform.primaryInput.id;
  var transaction = resolver.createTextEditTransaction(lib);
  var unit = lib.definingCompilationUnit.node;

  unit.accept(new _IdentifierTransformer(transaction, identifierElement,
      '$importPrefix.$replacement'));

  if (transaction.hasEdits) {
    addImport(transaction, unit,
      'package:${id.package}/$generatedFilename', importPrefix);

    var printer = transaction.commit();
    var url = id.path.startsWith('lib/')
        ? 'package:${id.package}/${id.path.substring(4)}' : id.path;
    printer.build(url);
    transform.addOutput(new Asset.fromString(id, printer.text));
  } else {
    // No modifications, so just pass the source through.
    transform.addOutput(transform.primaryInput);
  }
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
          'import \'$uri\' as $alias;\n');
      return;
    } else if (directive is LibraryDirective) {
      libDirective = directive;
    }
  }

  // No imports, add after the library directive if there was one.
  if (libDirective != null) {
    transaction.edit(libDirective.endToken.offset + 2,
        libDirective.endToken.offset + 2,
        'import \'$uri\' as $alias;\n');
  }
}

class _IdentifierTransformer extends GeneralizingASTVisitor {
  final TextEditTransaction transaction;
  final TopLevelVariableElement original;
  final String replacement;

  _IdentifierTransformer(this.transaction, this.original, this.replacement);

  visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.bestElement == original.getter) {
      transaction.edit(node.beginToken.offset, node.endToken.end, replacement);
    }
    super.visitSimpleIdentifier(node);
  }

  visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.bestElement == original.getter) {
      transaction.edit(node.beginToken.offset, node.endToken.end, replacement);
      return;
    }

    super.visitPrefixedIdentifier(node);
  }

  // Skip over the contents of imports.
  visitImportDirective(ImportDirective d) {}
}

/**
 * Changes all references from original to replacement, maintaining the method
 * parameters of the original invocation.
 *
 * [original] must be a reference to a static function.
 */
void transformMethodInvocations(TextEditTransaction transaction,
    CompilationUnit unit, FunctionElement original, String replacement) {
  unit.accept(new _FunctionTransformer(transaction, original, replacement));
}


class _FunctionTransformer extends GeneralizingASTVisitor {
  final TextEditTransaction transaction;
  final FunctionElement candidate;
  final String replacement;

  _FunctionTransformer(this.transaction, this.candidate, this.replacement);

  visitMethodInvocation(MethodInvocation m) {
    if (m.methodName.bestElement == candidate) {
      if (m.target is SimpleIdentifier) {
        // Include the prefix in the rename.
        transaction.edit(m.target.beginToken.offset, m.methodName.endToken.end,
            replacement);
      } else {
        transaction.edit(m.methodName.beginToken.offset,
            m.methodName.endToken.end, replacement);
      }
    }
    super.visitMethodInvocation(m);
  }

  // Skip over the contents of imports.
  visitImportDirective(ImportDirective d) {}
}

bool canImportAsset(AssetId id) => id.path.startsWith('lib/');

