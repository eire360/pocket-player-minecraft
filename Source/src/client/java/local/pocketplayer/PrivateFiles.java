package local.pocketplayer;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.util.Set;

/** Local coordination files: private to the OS account, not an authentication boundary within it. */
final class PrivateFiles {
    private static final Set<PosixFilePermission> DIR = PosixFilePermissions.fromString("rwx------");
    private static final Set<PosixFilePermission> FILE = PosixFilePermissions.fromString("rw-------");
    static void directory(Path path) throws IOException {
        try { Files.createDirectory(path, PosixFilePermissions.asFileAttribute(DIR)); }
        catch (FileAlreadyExistsException ignored) { }
        PosixFileAttributes attr=Files.readAttributes(path,PosixFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
        if (!attr.isDirectory() || !attr.owner().equals(Files.getOwner(Path.of(System.getProperty("user.home"))))) {
            throw new IOException("Local connection directory has an unsafe owner or file type.");
        }
        Files.setPosixFilePermissions(path,DIR);
    }
    static void write(Path destination,String content) throws IOException {
        directory(destination.getParent());
        Path temp=Files.createTempFile(destination.getParent(),".private-",".tmp",PosixFilePermissions.asFileAttribute(FILE));
        try {
            Files.writeString(temp,content,StandardOpenOption.WRITE,StandardOpenOption.TRUNCATE_EXISTING);
            Files.move(temp,destination,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
        } finally { Files.deleteIfExists(temp); }
    }
}
