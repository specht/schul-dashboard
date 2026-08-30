<?php

declare(strict_types=1);

if ($argc !== 3) {
    fwrite(STDERR, "Usage: nextcloud-share-move-worker.php NEXTCLOUD_ROOT RPC_DIR\n");
    exit(2);
}

$nextcloudRoot = rtrim($argv[1], '/');
$rpcDir = rtrim($argv[2], '/');
$requestsDir = $rpcDir . '/requests';
$responsesDir = $rpcDir . '/responses';
$readyPath = $rpcDir . '/ready';
$stopPath = $rpcDir . '/stop';

error_reporting(E_ALL);
ini_set('display_errors', 'stderr');
define('OC_CONSOLE', 1);

try {
    require_once $nextcloudRoot . '/lib/base.php';

    $shareManager = \OC::$server->get(\OCP\Share\IManager::class);
    $userManager = \OC::$server->get(\OCP\IUserManager::class);
    $eventDispatcher = \OC::$server->get(\OCP\EventDispatcher\IEventDispatcher::class);

    if (!is_dir($requestsDir) || !is_dir($responsesDir)) {
        throw new RuntimeException('RPC request/response directories do not exist');
    }

    file_put_contents($readyPath, (string)getmypid());

    while (!file_exists($stopPath)) {
        $requestPaths = glob($requestsDir . '/*.json') ?: [];

        foreach ($requestPaths as $requestPath) {
            $requestId = basename($requestPath, '.json');
            $responsePath = $responsesDir . '/' . $requestId . '.json';
            $responseTmpPath = $responsePath . '.tmp';

            try {
                $request = json_decode((string)file_get_contents($requestPath), true, 512, JSON_THROW_ON_ERROR);

                foreach (['share_id', 'recipient', 'expected_owner', 'target'] as $key) {
                    if (!isset($request[$key]) || !is_string($request[$key]) || $request[$key] === '') {
                        throw new InvalidArgumentException("Missing or invalid request field: {$key}");
                    }
                }

                $share = $shareManager->getShareById('ocinternal:' . $request['share_id'], $request['recipient']);

                if ($share->getShareType() !== \OCP\Share\IShare::TYPE_USER) {
                    throw new RuntimeException('Refusing to move a non-user share');
                }
                if ($share->getSharedWith() !== $request['recipient']) {
                    throw new RuntimeException('Share recipient changed before move');
                }
                if ($share->getShareOwner() !== $request['expected_owner']) {
                    throw new RuntimeException('Share owner changed before move');
                }

                // getShareById(..., $recipient) resolves the share in the
                // recipient's mount context. If a mount-name collision exists,
                // Nextcloud can therefore return e.g. "/Ausgabeordner (7)"
                // even though the OCS share record exposed "/Ausgabeordner".
                // The share ID, type, recipient and owner checks above uniquely
                // identify the share; comparing those two target representations
                // is not a valid concurrency guard.
                $currentTarget = $share->getTarget();
                if ($currentTarget !== $request['target']) {
                    $share->setTarget($request['target']);
                    $share = $shareManager->moveShare($share, $request['recipient']);
                }

                $user = $userManager->get($request['recipient']);
                if ($user !== null) {
                    $eventDispatcher->dispatchTyped(
                        new \OCP\Files\Events\InvalidateMountCacheEvent($user)
                    );
                }

                $response = [
                    'ok' => true,
                    'share_id' => $share->getId(),
                    'previous_target' => $currentTarget,
                    'target' => $share->getTarget(),
                ];
            } catch (Throwable $e) {
                $response = [
                    'ok' => false,
                    'error_class' => get_class($e),
                    'message' => $e->getMessage(),
                ];
            }

            file_put_contents(
                $responseTmpPath,
                json_encode($response, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)
            );
            rename($responseTmpPath, $responsePath);
            @unlink($requestPath);
        }

        usleep(20_000);
    }
} catch (Throwable $e) {
    fwrite(STDERR, 'Nextcloud share move worker failed: ' . get_class($e) . ': ' . $e->getMessage() . "\n");
    exit(1);
} finally {
    @unlink($readyPath);
}
